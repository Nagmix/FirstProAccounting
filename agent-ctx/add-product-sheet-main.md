# Task: Create AddProductSheet Multi-Step Wizard

## Summary
Completely rewrote `/home/z/my-project/FirstProAccounting/firstpro/lib/ui/screens/products/add_product_sheet.dart` (1860 lines) as a production-ready multi-step wizard for adding/editing products in an Arabic RTL accounting app.

## Key Changes
- **8-step wizard** with step indicator (progress dots/circles at top)
- Steps: البيانات الأساسية → الوحدات → الأسعار → المخزون → الموردين → الباركود → إعدادات البيع → المحاسبة
- Navigation buttons at bottom: السابق / التالي / حفظ
- PageController + PageView for step navigation with animation
- All Arabic labels, RTL layout via Directionality widget
- Loads units from DB via `DatabaseHelper().getAllUnits()`
- Base unit dropdown filtered by `is_base_unit=1`
- Smart conversion UX: "الكرتون كم حبة؟" style labels
- Opening stock movement for new products via `logStockMovement`
- Edit mode locks stock, warehouse, and accounting fields
- Proper use of `withValues(alpha:)` instead of `withOpacity()`
- `isDense: true` inside InputDecoration only (not on TextField/TextFormField)
- DropdownButtonFormField uses `isDense` as direct parameter
- Price fields use `FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))`
- Unit conversions include `from_unit_id` and `to_unit_id` for DB
