# Task: Add Inventory Voucher (سند الجرد) and Annual Posting (الترحيل السنوي)

## Agent: developer

## Summary

Both features were **already fully implemented** by a previous agent at DB version 22. I verified all components and made only the necessary adjustments:

### Changes Made

1. **Bumped DB version from 22 to 23** in:
   - `lib/data/datasources/database_helper.dart` (line 12)
   - `lib/core/constants/app_constants.dart` (line 14)

2. **Added UNIQUE constraint on `fiscal_years.year`** column:
   - Updated `_onCreate` table definition: `year INTEGER NOT NULL UNIQUE` (was `year INTEGER NOT NULL`)
   - Added v23 migration in `_onUpgrade`: Recreates `fiscal_years` table with UNIQUE constraint using temp table approach (SQLite doesn't support ALTER TABLE ADD UNIQUE)

### Already Implemented (Verified)

#### Feature 1: Inventory Voucher (سند الجرد)

**Database:**
- `inventory_vouchers` table - Created in `_onCreate` and v22 migration
- `inventory_voucher_items` table - Created in `_onCreate` and v22 migration
- `insertInventoryVoucher()` method - Full implementation with:
  - Header and items insertion
  - Product stock updates based on difference
  - Journal entries: increase→Debit Inventory/Credit COGS; decrease→Debit COGS/Credit Inventory
  - Uses `_updateAccountBalanceWithJournal` for balance updates
  - Uses `_findAccountByCodeAndCurrency` for multi-currency support
- `getInventoryVouchers()` - With search and warehouse name join
- `getInventoryVoucherDetails()` - With items and product details
- `getNextInventoryVoucherNumber()` - Auto-generates IV-YYYYMM-XXXX format

**UI:**
- `inventory_voucher_screen.dart` - List screen with search, date filter, detail modal
- `create_inventory_voucher_screen.dart` - Creation form with product selection, system/actual quantity, difference calculation

**Navigation:**
- Route constant `inventoryVoucher = '/vouchers/inventory'` in app_constants.dart
- Route registered in app_router.dart
- Entry in settings_screen.dart (under المخزون section)
- Entry in reports_screen.dart (under _reportTypes as 'سند الجرد')

#### Feature 2: Annual Posting (الترحيل السنوي)

**Database:**
- `fiscal_years` table - Created in `_onCreate` and v22 migration
- `performAnnualPosting(int year)` method - Full implementation with:
  - Check if fiscal year already closed
  - Calculate net profit per currency: revenue - costs - expenses
  - Close revenue accounts: Debit each revenue, Credit Retained Earnings
  - Close cost accounts: Debit Retained Earnings, Credit each cost
  - Close expense accounts: Debit Retained Earnings, Credit each expense
  - Create/update fiscal_years record with status='closed'
- `getFiscalYears()` - List all fiscal years ordered by year DESC
- `isFiscalYearClosed(int year)` - Check if year is closed
- `getYearProfitLoss(int year)` - Get P&L breakdown for a year

**UI:**
- `annual_posting_screen.dart` - Full screen with:
  - Current year P&L breakdown
  - Fiscal year status (open/closed) badge
  - "ترحيل سنوي" button (only if not closed)
  - Confirmation dialog requiring typing "تأكيد"
  - Fiscal years history list

**Navigation:**
- Route constant `annualPosting = '/reports/annual-posting'` in app_constants.dart
- Route registered in app_router.dart
- Entry in settings_screen.dart (under المحاسبة section)
- Entry in reports_screen.dart (under _reportTypes as 'الترحيل السنوي')
