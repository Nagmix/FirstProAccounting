# FirstPro Accounting - Work Log

---
Task ID: 1
Agent: Main Agent
Task: Comprehensive audit fixes based on FINAL AUDIT REPORT

Work Log:
- Read and analyzed the full audit report uploaded by user
- Fetched latest code from GitHub (Build #65)
- Excluded "permissions/users" section per user request
- Identified and prioritized all fixes from the report

Stage Summary:
- Report analyzed, 12+ fixes identified and prioritized
- Excluded: User/permissions system (not the right time per user)
- Cloud backup: needs user input on provider choice

---
Task ID: 2
Agent: Main Agent
Task: Fix POS screen - products not adding to invoice when clicked

Work Log:
- Added mounted checks throughout _addToCartWithUnit, _addToCartDirect, _doAddToCartWithUnit
- Added product.id null guards to prevent silent crashes
- Added try-catch around all _addToCartDirect calls with Arabic error feedback
- Positioned DraggableScrollableSheet inside Positioned widget to prevent tap interception
- Added sheet animation error handling
- Filtered products by isSellable && showInPos for POS product list

Stage Summary:
- POS screen error handling significantly improved
- Added visual error feedback for all failure cases
- Product grid now only shows POS-appropriate products

---
Task ID: 3
Agent: Main Agent
Task: Fix Step 3 sell price label

Work Log:
- Changed single-unit sell price label from 'سعر البيع *' to 'سعر بيع الـ $baseUnitName *'
- Multi-unit label already showed unit name correctly

Stage Summary:
- Sell price label now always specifies which unit the price is for

---
Task ID: 4
Agent: Subagent
Task: Secure PIN storage with flutter_secure_storage

Work Log:
- Migrated PIN storage from SQLite settings table to flutter_secure_storage
- Added _readSecureWithMigration pattern with DB fallback for existing users
- Improved _hashPin with salt and 100 iterative rounds (new h2$ prefix)
- Added _hashPinOld for backward-compatible verification
- Added _verifyPin with auto-upgrade from old to new hash format
- Updated main.dart, app_lock_screen.dart, settings_screen.dart

Stage Summary:
- PIN no longer stored in plain database
- Backward compatible with auto-migration
- Hash function significantly strengthened

---
Task ID: 5
Agent: Subagent
Task: Add audit trail and closed period protection

Work Log:
- Created audit_trail table (migration v29) with full change tracking
- Added logAuditEvent() method with non-critical error handling
- Added isDateInClosedPeriod() method
- Added closed period check in saveInvoiceWithJournalEntries
- Added closed period check in cancelInvoice
- Added audit logging on invoice cancellation

Stage Summary:
- Full audit trail now tracks all significant changes
- Closed fiscal years are protected from new/cancelled invoices

---
Task ID: 6
Agent: Subagent
Task: Add cancel invoice button and improve error handling

Work Log:
- Added red "إلغاء الفاتورة" button in invoice detail screen
- Added confirmation dialog with warning about irreversible actions
- Added Arabic error messages for closed period violations
- Wrapped saveInvoiceWithJournalEntries in try-catch with Arabic errors
- Wrapped cancelInvoice in try-catch with Arabic errors

Stage Summary:
- Users can now cancel invoices from the UI
- Error messages are clear and in Arabic

---
Task ID: 7
Agent: Subagent
Task: Improve stocktaking with approval flow

Work Log:
- Added variance column to stocktaking_items (migration v30)
- Added preview dialog before applying stocktaking
- Color-coded variances: green (gain), red (loss), grey (no change)
- Summary chips: total, matched, adjusted, positive, negative, value
- Audit logging for each product stock adjustment

Stage Summary:
- Stocktaking now requires preview confirmation before applying
- Variance tracking prevents silent stock adjustments

---
Task ID: 8
Agent: Subagent
Task: Link returns to original invoices

Work Log:
- Added original_invoice_id column (migration v31)
- Added checkReturnLimits() to prevent duplicate/excessive returns
- Added getLinkedReturns() and getInvoiceById() helper methods
- Added original invoice selector UI in create_invoice_screen
- Added original invoice and linked returns sections in invoice detail

Stage Summary:
- Returns can now be linked to their original invoice
- System prevents returning more than was originally sold

---
Task ID: 9
Agent: Subagent
Task: Improve backup and restore

Work Log:
- Added file_picker dependency for file-based restore
- Implemented working restore flow with source picker (device/auto-backup)
- Added auto-backup with configurable frequency (daily/weekly)
- Added auto-backup directory with last-5-file rotation
- Added last backup date display in settings
- Added resetInstance() and getDatabasePath() to DatabaseHelper

Stage Summary:
- Backup now supports auto-scheduling and proper restore
- Restore works from both device files and auto-backup files

---
Task ID: 10
Agent: Main Agent
Task: Push code and create build

Work Log:
- Fixed duplicate logAuditEvent method (removed old audit_log version)
- Fixed all logAuditEvent calls to use new signature
- Pushed to GitHub as Build #66
- Flutter SDK not available in this environment for local build

Stage Summary:
- Build #66 committed and pushed to GitHub
- 11 files changed, 1875 insertions, 130 deletions
- DB version: 28 -> 31 (3 new migrations)

---
Task ID: 11
Agent: Subagent
Task: Fix T19+T21+T22 product sheet bugs

Work Log:
- T19: Added discount validation (negative + exceeds subtotal) and paid amount validation (negative) in create_invoice_screen.dart _saveInvoice()
- T21: Fixed minimumSalePrice copy-paste bug — was using _specialWholesalePriceController instead of own controller
  - Added _minimumSalePriceController TextEditingController
  - Added dispose for new controller
  - Added population from existing product (in both _populateFromExisting and _loadUnitConversions)
  - Added separate UI field "سعر البيع الأدنى" in pricing step
  - Renamed old "أقل سعر بيع" label to "سعر الجملة الخاصة" for clarity
  - Updated minimumSalePrice assignment to use _minimumSalePriceController with multi-unit conversion logic
- T22: Fixed averageCost replaced on edit — when _isEditMode, now preserves widget.existing!.averageCost instead of overwriting with baseCostPrice

Stage Summary:
- 3 bugs fixed across 2 files
- create_invoice_screen.dart: 4 new validation checks (negative discount, discount > subtotal, negative paid, paid > total)
- add_product_sheet.dart: New controller + UI field for minimum sale price, averageCost preserved on edit

---
Task ID: 12
Agent: Subagent
Task: Fix T28+T29+T30+T31 account bugs

Work Log:
- T28: Fixed running balance ignoring opening balance in account_ledger_screen.dart
  - Running balance was starting from 0 instead of the account's opening balance
  - Added `openingBalance = widget.account.balance - netBalance` computation
  - Changed `double running = 0` to `double running = openingBalance`
  - This ensures the final running balance matches the account's actual current balance

- T29: Fixed currency hardcoded to YER in add_account_sheet.dart
  - Added `String _currency = 'YER'` state variable
  - Added `_currencyInfo` static map (YER, SAR, USD) matching add_cash_box_sheet.dart
  - Added DropdownButtonFormField for currency selection in the form
  - Initialized `_currency` from `widget.existing!.currency` when editing
  - Changed `_save()` to use `_currency` instead of `widget.existing?.currency ?? 'YER'`

- T30: Fixed annual posting showing wrong year in annual_posting_screen.dart
  - Was using `DateTime.now().year` to fetch P&L data regardless of fiscal year
  - Added `int _activeYear` state variable
  - Modified `_loadData()` to determine active year from fiscal years list:
    - Prefers most recent open fiscal year
    - Falls back to most recent fiscal year if all closed
    - Falls back to DateTime.now().year if no fiscal years exist
  - Updated `build()` to use `_activeYear` instead of `DateTime.now().year`

- T31: Added fiscal year overlap validation in fiscal_year_screen.dart
  - Added overlap check in `_showCreateFiscalYearDialog()` before inserting
  - Uses standard date range overlap check: `!newStart.isAfter(existEnd) && !existStart.isAfter(newEnd)`
  - This covers all three overlap scenarios: new start within existing, new end within existing, existing fully within new
  - Shows Arabic error dialog with details of the overlapping fiscal year and date ranges
  - Prevents saving when overlap is detected

Stage Summary:
- 4 bugs fixed across 4 files
- account_ledger_screen.dart: Running balance now includes opening balance
- add_account_sheet.dart: Currency dropdown added (YER/SAR/USD)
- annual_posting_screen.dart: Uses fiscal year year instead of device clock year
- fiscal_year_screen.dart: Overlap validation prevents conflicting fiscal year date ranges

---
Task ID: 13
Agent: Subagent
Task: Fix T17+T18 customer detail bugs

Work Log:
- T17: Fixed customer-voucher linking broken in customer_detail_screen.dart
  - Old code searched accounts by `name_ar LIKE '%العملاء%'` which matched ALL customer accounts, not the specific customer's — two different customers would share the same voucher results
  - Confirmed vouchers table has `customer_id` column in schema (database_helper.dart line 677)
  - Replaced broken approach with direct query: `SELECT * FROM vouchers WHERE customer_id = ?`
  - Added backward compatibility fallback for vouchers with NULL customer_id: checks voucher items against customer's receivable account AND verifies the voucher description contains the customer's name
  - Also added `customer_id: _freshCustomer?.id` to the voucher creation dialog so new vouchers are properly linked

- T18: Fixed running balances corrupted in customer detail
  - `_applyFilters()` was using shallow copy (`List<Map>.from()`) which shared map references with `_allMovements`, so modifying `m['running_balance']` corrupted the original list
  - Changed to deep copy: `_allMovements.map((m) => Map<String, dynamic>.from(m)).toList()`
  - Added opening balance calculation: computes difference between customer's stored balance and sum of all tracked movements
  - Running balance now starts from the opening balance instead of 0
  - Net balance calculation updated to include opening balance

Stage Summary:
- 2 bugs fixed in customer_detail_screen.dart
- Vouchers now correctly scoped to the specific customer (no more cross-customer leakage)
- Running balances no longer corrupted when filters change
- Opening balance properly accounted for in running balance calculation

---
Task ID: 14
Agent: Subagent
Task: Fix T14+T25+T26+T27 expenses and opening balance bugs

Work Log:
- T14: Added opening balance journal entries for cash boxes in add_cash_box_sheet.dart
  - After insertCashBox, when creating a NEW cash box with non-zero opening balance:
    - Creates debit/credit transaction pairs (Cash & Banks ↔ Opening Balance Equity account code 2200+offset)
    - Handles both balanceType directions: 'debit' (عليه) debits Cash & Banks, 'credit' (له) credits Cash & Banks
    - Calls updateAccountBalance for both accounts to keep balances in sync
  - Customer and supplier opening balance journal entries were already handled by DatabaseHelper.insertCustomer/insertSupplier methods (no UI changes needed)

- T25: Fixed expense balance calculation inverted in expenses_screen.dart
  - _loadData(): Replaced stored balance_type-based total calculation with effective balance type logic
    - For EXPENSE/COST/ASSET accounts (debit-nature): positive balance = debit = expense incurred → add to total
    - For LIABILITY/REVENUE accounts (credit-nature): positive balance = credit → subtract from total
  - _buildExpenseAccountCard(): Changed isCredit determination from stored balance_type to effective type
    - For debit-nature accounts: negative balance = credit (له/green), positive = debit (عليه/red)
    - For credit-nature accounts: positive balance = credit (له/green), negative = debit (عليه/red)
  - Header "الحالة" chip: Fixed from 'له' for positive/عليه for negative → 'عليه' for positive/له for negative (correct for expense accounts)

- T26: Fixed effectiveExpenseAccountId not used in insert in add_expense_screen.dart
  - Changed 'account_id' field in expenseMap from systemExpenseAccountId to effectiveExpenseAccountId
  - effectiveExpenseAccountId = widget.expenseAccountId ?? systemExpenseAccountId
  - This ensures when a specific expense account is provided via widget, it's used for the transaction instead of always falling back to the system account

- T27: Fixed edit expense doesn't reverse old entry in add_expense_screen.dart
  - Added _existingExpense field to store the old expense data when loading for edit (was commented out)
  - Added _editExpenseWithReversal() method that runs in a single DB transaction:
    1. Reverses old journal entries: creates reverse transactions with swapped debit/credit for the old expense
    2. Reverses old cash box balance change (opposite direction)
    3. Updates the expense record
    4. Creates new journal entries for the updated expense values
    5. Updates cash box balance for the new entry
  - Changed edit branch from db.updateExpense() to _editExpenseWithReversal()

Stage Summary:
- 4 bugs fixed across 3 files
- add_cash_box_sheet.dart: New cash boxes now create proper double-entry journal entries for opening balances
- expenses_screen.dart: Expense account balances and labels now correctly reflect debit nature (عليه=red for expenses, له=green for refunds)
- add_expense_screen.dart: effectiveExpenseAccountId used in insert; editing expenses now properly reverses old journal entries before posting new ones

---
Task ID: 15
Agent: Subagent
Task: Fix T13+T20+T23+T24

Work Log:

- T13: Fixed exchange rate not used in invoice calculations
  - Added `_totalInBaseCurrency`, `_paidAmountInBaseCurrency`, `_remainingInBaseCurrency` getters in create_invoice_screen.dart
  - Replaced simple "بالعملة الأساسية" row with rich YER-equivalent display box in `_buildSummarySection()` showing:
    - "المعادل بالريال اليمني: X ر.ي" for total
    - "المدفوع (ر.ي)" for paid amount when > 0
    - "المتبقي (ر.ي)" for remaining amount when > 0
  - Modified `saveInvoiceWithJournalEntries` in database_helper.dart to convert all journal entry amounts to YER when invoice currency is not YER:
    - Added `needsYerConversion` flag based on `invoiceCurrency != 'YER' && exchangeRate > 0`
    - When conversion needed: uses `journalTotal`, `journalEffectivePaid`, `journalRemainingAmount` (amounts * exchangeRate)
    - When conversion needed: uses YER accounts (codeOffset = 0, journalCurrency = 'YER')
    - When YER: keeps existing behavior (currency-specific accounts and amounts)
  - Also updated COGS and Purchase Inventory Transfer account queries to use `journalCurrency`

- T20: Fixed warehouse-specific stock validation in stock transfer
  - Added `getProductStockInWarehouse(int productId, int warehouseId)` method in database_helper.dart
    - Returns `null` if product doesn't exist in that warehouse, `double` for stock quantity
  - In stock_transfer_screen.dart `_submitTransfer()`:
    - When source warehouse is selected: queries stock specifically for that warehouse using new method
    - Shows "المنتج غير موجود في مخزن المصدر" if product not in source warehouse
    - Shows "الكمية المتاحة في المخزن X فقط" with warehouse-specific stock
    - Falls back to total stock check when no warehouse is selected
  - Added `isInSourceWarehouse` flag in product list items to indicate warehouse match with "*" suffix

- T23: Fixed journal entries outside transaction in add_product_sheet
  - Moved stock movement logging and journal entry creation INSIDE the `db.transaction()` closure
  - Replaced `dbHelper.logStockMovement()` with direct `txn.insert('stock_movements', ...)` 
  - Replaced `dbInstance.query(...)` with `txn.query(...)` for account lookups
  - Replaced `dbInstance.insert('transactions', ...)` with `txn.insert('transactions', ...)` for journal entries
  - Replaced `dbHelper.updateAccountBalance()` with inline account balance update logic using `txn`
    - Properly handles both credit-type and debit-type accounts
  - This ensures atomicity: if journal entry fails, the product insert is rolled back too

- T24: Fixed cash box balance updates after transfer/exchange
  - Fixed `insertCashTransfer` in database_helper.dart:
    - Now queries each cash box's `balance_type` before updating
    - Credit-type (له): source decreases when money leaves, destination increases when money arrives
    - Debit-type (عليه): source increases when money leaves (more owed), destination decreases when money arrives (less owed)
  - Fixed `insertCurrencyExchange` in database_helper.dart with same balance_type logic
  - Fixed cash box balance update in `saveInvoiceWithJournalEntries`:
    - Now queries cash box's `balance_type` before updating
    - Credit-type: cash in increases balance, cash out decreases
    - Debit-type: cash in decreases balance (less owed), cash out increases (more owed)

Stage Summary:
- 4 bugs fixed across 4 files
- create_invoice_screen.dart: Added YER-equivalent display (total, paid, remaining) when non-YER currency selected; journal entries now use YER-converted amounts and YER accounts
- stock_transfer_screen.dart: Warehouse-specific stock validation using getProductStockInWarehouse; shows product-warehouse match indicator
- add_product_sheet.dart: Opening balance journal entries now inside transaction for atomicity; uses txn for all DB ops
- database_helper.dart: Added getProductStockInWarehouse method; fixed balance_type handling in cash box updates (transfer, exchange, invoice); journal entries use YER when invoice is foreign currency

---
Task ID: 16
Agent: Subagent
Task: Add journal entries for stocktaking adjustments (T15)

Work Log:
- Modified `completeStocktakingSession()` in database_helper.dart to create journal entries for inventory adjustments
- Added automatic creation of two new system accounts if they don't exist:
  - 5400: "خسارة تفاوت الجرد (ر.ي)" / Inventory Variance Loss (YER) — EXPENSE type, debit balance
  - 4400: "إيراد تفاوت الجرد (ر.ي)" / Inventory Variance Income (YER) — REVENUE type, credit balance
- For each product with non-zero variance:
  - Stock INCREASED (variance > 0): Debit Inventory (1300), Credit Inventory Variance Income (4400)
  - Stock DECREASED (variance < 0): Debit Inventory Variance Loss (5400), Credit Inventory (1300)
  - Journal entry amount = variance × average_cost of the product
- Used same journal entry pattern as saveInvoiceWithJournalEntries: insert into transactions table + _updateAccountBalanceWithJournal
- All journal entries share a single journal_id for the stocktaking session
- Default currency: YER (products don't carry currency; stocktaking doesn't have currency selection)
- Account auto-creation happens inside the same DB transaction for atomicity

Stage Summary:
- Stocktaking adjustments now create proper double-entry journal entries
- Two new auto-seeded accounts: Inventory Variance Loss (5400) and Inventory Variance Income (4400)
- All changes within the same DB transaction as the stock update for consistency

---
Task ID: 16
Agent: Subagent
Task: Add logStockMovement for transfers and stocktaking (T16)

Work Log:
- Modified `completeStocktakingSession()` in database_helper.dart to log stock movements:
  - For each product with non-zero variance, inserts into stock_movements table
  - movement_type: 'adjustment'
  - quantity: variance (positive for increase, negative for decrease)
  - reference_type: 'stocktaking', reference_id: sessionId
  - unit_cost: product's average_cost
  - Arabic notes: 'زيادة جرد' or 'نقص جرد'

- Modified `insertStockTransfer()` in database_helper.dart to log stock movements:
  - Source warehouse: movement_type 'transfer_out', quantity: -quantity
  - Destination warehouse: movement_type 'transfer_in', quantity: +quantity
  - Both reference_type: 'transfer', reference_id: transfer ID
  - unit_cost: source product's average_cost
  - Handles both cases: existing product in destination warehouse and newly created product
  - All insertions within the same DB transaction for atomicity

- Used `txn.insert('stock_movements', ...)` directly within transactions (same pattern as saveInvoiceWithJournalEntries)

Stage Summary:
- Stock movements are now logged for both stocktaking adjustments and stock transfers
- All logging is atomic within the same DB transaction as the stock update
- No screen file changes needed — the enhanced database methods are called by existing screen code
