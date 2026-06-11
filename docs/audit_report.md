# 🔍 الملف المرجعي الشامل — فحص وتتبع مشاكل FirstProAccounting
**المستودع:** https://github.com/Nagmix/FirstProAccounting
**هذا الملف هو المرجع الحي لكل المشاكل والمهام** — يُحدَّث عند اكتشاف أي مشكلة جديدة وعند إنجاز أي مهمة.

| | |
|---|---|
| تاريخ الفحص الأول | 2026-06-10 (commit `5920b69`) |
| آخر تحديث | 2026-06-10 — بعد إنجاز المرحلة الأولى من B-1.7 (commit `1159bdd`) |
| أداة الفحص | Flutter 3.32.5 / Dart 3.8.1 — analyze + test + فحص يدوي |

## 🏷️ دليل الحالات
- ✅ **منجزة** — أُصلحت وتحقّقنا منها (analyze + tests)
- 🔶 **غير مكتملة** — أُصلحت جزئياً أو قيد التنفيذ المرحلي
- ❌ **غير منجزة** — لم يبدأ العمل عليها
- 👁️ **قيد المناقشة** — بانتظار قرار المالك

---

## 📊 خط الأساس الحالي (تحديث 2026-06-10)

| الفحص | الفحص الأول | قبل الجولة الحالية | **الآن (1159bdd)** |
|---|---|---|---|
| `flutter analyze` errors/warnings | 0 / 0 | 0 / 0 | **0 / 0** ✅ |
| `flutter analyze` infos | 2790 | 851 | **~855** (تغيرات هيكلية) |
| `flutter test` | 543 ناجحة | 575 ناجحة | **575 ناجحة** ✅ |
| إصدار قاعدة البيانات | v49 | v50 | **v52** ✅ |

---

# 🐛 القسم أ: الأخطاء الوظيفية (Bugs)

## A-1 ✅ مشكلة فرز الحركات والرصيد التراكمي — **مُصلحة**
**الحالة:** ✅ منجزة (commit `ea5cd54`)

## A-2 ✅ ترحيل مزدوج في سند القبض/الصرف — **مُصلحة**
**الحالة:** ✅ منجزة (commit `eeabbe8`)

## A-3 ✅ حذف الفاتورة لا يعكس الأرصدة ولا يعيد المخزون — **مُصلحة**
**الحالة:** ✅ منجزة (commit `1dfde76`)

## A-7 ✅ الفواتير الأجنبية تُقيَّد بالعملة المحلية (تناقض معماري) — **مُصلحة**
**الحالة: ✅ منجزة (commit `ccdc644`)**
- تم توحيد نموذج ترحيل الفواتير مع السندات.
- القيود ترحل بعملتها الأصلية على حسابات تلك العملة.
- الاحتفاظ بـ `amount_base` للتقارير الموحدة.

## A-8 🔶 العملات ليست ديناميكية — **قيد التنفيذ (المرحلة الثانية)**
**الحالة: 🔶 غير مكتملة (إنجاز البنية التحتية في commit `1159bdd`)**
- تم إلغاء نظام `codeOffset` الثابت واستبداله بـ `code_offset` في جدول العملات.
- تم إضافة `base_code` لجدول الحسابات لربط الحسابات وظيفياً عبر العملات.
- تم تفعيل أتمتة إنشاء شجرة الحسابات لأي عملة جديدة تضاف للنظام.
- المتبقي: جعل قوائم الواجهات ديناميكية وتحديث POS والعملة الأساس.

## A-9 ✅ خلط عملات في تقييم المخزون — **مُصلحة**
**الحالة: ✅ منجزة (commit `ccdc644`)**
- تقييم المخزون (`average_cost`) أصبح يتم بالعملة الأساس (YER) دائماً.
- يتم تحويل أسعار الشراء الأجنبية بسعر الصرف التاريخي قبل دخولها في معادلة التكلفة (IAS 2).

---

# 🛠️ القسم ب: خطة الإصلاحات الرئيسية

| # | المهمة | الحالة | ملاحظات |
|---|---|---|---|
| B-0 | إصلاح الترحيل المزدوج A-2 | ✅ منجزة | commit `eeabbe8` |
| B-1 | إصلاح مشكلة الفرز A-1 جذرياً | ✅ منجزة | commit `ea5cd54` |
| B-1.5 | إصلاح حذف الفاتورة A-3 | ✅ منجزة | commit `1dfde76` |
| B-1.6 | **توحيد العملة A-7 + سلامة المخزون A-9 + A-10** | ✅ **منجزة** | commit `ccdc644` + `15c7fb0` — التزام بمعايير IAS 2/21، وسلامة المبالغ المالية |
| B-1.7 | **ديناميكية العملات A-8 + دعم تغيير الأساس** | ✅ **منجزة** | المرحلة 1 (البنية): ✅ (v51) / المرحلة 2 (الواجهات): ✅ (commit `5cbb092`) — تم استبدال جميع استخدامات `AppConstants.currency` الثابت في ~20 شاشة/ملف UI بـ `CurrencyConstants.currencySymbol(code)` الديناميكي. العملة تُحمّل من سياق الكيان (product/invoice/supplier/employee) أو من `vm.selectedCurrency` في POS. CI اجتاز بنجاح. |
| B-2 | استبدال `withOpacity` → `withValues` | ✅ منجزة | commit `23b24a0` |
| B-3 | `dart format` | ✅ منجزة | commit `9040c96` |
| B-4 | تحويل الاستيرادات النسبية → package imports | ✅ منجزة | commit `dc3509a` |
| B-10 | نظافة المستودع و README | ✅ منجزة | commit `e12068a` |
| B-14 | اختبار Migration v50 | ✅ منجزة | commit `1a75dab` |
| B-15 | حارس FK | ✅ منجزة | commit `e0629a9` |
| B-16 | إصلاح النسخ الاحتياطي والاستعادة | ✅ منجزة | commit `e3345a8` |

---

## A-10 ✅ مشكلة الضعف ×100 في المبالغ المالية — **مُصلحة**
**الحالة:** ✅ منجزة (commit `15c7fb0` + متابعة اختبارات)
- **السبب الجذري:** كانت جميع نماذج البيانات (`toMap`) تُحوّل المبالغ إلى سنتات (×100) قبل إرسالها للـ Repositories، ثم كانت الـ Repositories تستدعي `toCentsMap()` مرة ثانية، مما أدى إلى ضعف مزدوج (×10000).
- **الإصلاح:** تعديل `toMap()` في 11 نموذجاً لإرجاع قيم `double` قابلة للقراءة البشرية، وجعل `toCentsMap()` آمناً (idempotent) باستخدام حارس >100 مليون، وتحديث الـ Repositories لتستدعي `toCentsMap()` فقط عند نقطة الإدخال للقاعدة.
- **النماذج المُعدّلة:** Product, Account, Invoice, InvoiceItem, Customer, Supplier, CashBox, Expense, BankReconciliation, InventoryCostLayer, Transaction.
- **الاختبارات:** تم تصحيح جميع اختبارات الوحدات (unit tests) لتتطابق مع السلوك الجديد.

---

# 📜 القسم د: سجل العمليات (Changelog) - تحديثات الجولة الحالية

| التاريخ | الحدث |
|---|---|
| 2026-06-10 | **إنجاز B-1.6 (IAS 2/21 Integration):** إصلاح جذري لتقييم المخزون بالعملة الأساس وترحيل الفواتير الأجنبية على حساباتها الصحيحة مع توازن `amount_base`. |
| 2026-06-10 | **إنجاز المرحلة الأولى من B-1.7:** ترحيل قاعدة البيانات v51، إضافة `code_offset` و `base_code` بشكل ديناميكي، إنشاء خدمة `BaseCurrencyService` وربطها بالـ DI، وأتمتة إنشاء الحسابات للعملات الجديدة في `ReferenceDataRepository`. |
| 2026-06-10 | **إصلاح B-16:** حل مشكلة فشل استعادة النسخة الاحتياطية المشفّرة وتعديل واجهة اختيار مجلد الحفظ. |
| 2026-06-10 | **استقرار الـ CI:** معالجة أخطاء التحليل البرمجي الناتجة عن التعديلات الهيكلية وضمان نجاح بناء الـ APK في GitHub Actions. |
| 2026-06-11 | **إصلاح A-10 (×100 Bug):** إصلاح جذري لمشكلة الضعف ×100 في المبالغ المالية بإزالة التحويل المزدوج بين `toMap` و `toCentsMap`، وتحديث 11 نموذجاً و3 Repositories و4 ملفات اختبارات وحدات. تم التحقق من نجاح 567 اختباراً ومعالجة 8 اختبارات فاشلة لتتوافق مع السلوك الجديد. |
| 2026-06-11 | **متابعة A-10:** تم العثور على `MoneyHelper.toCents()` متبقٍ في `Invoice.toMap()` لحقل `transport_charges`، تم تصحيحه. CI اجتاز بـ **0 فاشلات** (run `27316668537`). |
| 2026-06-11 | **B-1.7 المرحلة 2 (Phase 2):** ديناميكية العملات في الواجهات — تم استبدال `AppConstants.currency` الثابت في 13 ملف UI بـ `CurrencyConstants.currencySymbol(code)` الديناميكي. CI اجتاز بنجاح (run `27317248644`). |
| 2026-06-11 | **فحص شامل للمشروع:** تم إجراء فحص شامل يدوي للكود (218 ملف .dart) واستخراج المشاكل المتبقية (C-01, C-03, I-01..I-05, E-01..E-03). |
| 2026-06-11 | **إنجاز A-12 (C-03 VAT Configurability):** إضافة `vat_rate` لجدول `currencies` (migration v52)، تحديث `InvoiceViewModel` و `PosViewModel` لقراءة VAT rate من العملة المختارة، تحديث الواجهات (`create_invoice_screen`, `invoice_summary_section`, `pos_screen`, `add_product_sheet`) لاستخدام VAT rate الديناميكي، وإزالة `AppConstants.defaultVatRate` الثابت. |
| 2026-06-11 | **إنجاز المجموعة الأولى (I-01 → I-05):** I-01 تحقق (readMoney يعمل بشكل صحيح). I-02 تفعيل `unit_cost` في `InvoiceItem` (عرض في UI + تمرير عند الإنشاء + تمرير في itemsMaps عند الحفظ). I-04 إضافة `transport_charges` إلى POS (ViewModel + UI + Checkout). I-05 تحقق (columns موجودة في schema + migration v46). |

---

# 🐛 القسم أ (متابعة): أخطاء جديدة مكتشفة في الفحص الشامل 2026-06-11

## A-11 ✅ استخدام Hardcoded `codeOffset` — **مُصلحة (فحص 2026-06-11)**
**الحالة:** ✅ منجزة (تم التحقق يدوياً من الكود الحالي)
**الوصف:** تم فحص جميع الملفات المذكورة في التقرير السابق. تبيّن أن كافة الـ Repositories والخدمات (`invoice_repository`, `cash_box_service`, `customer_repository`, `expense_repository`, `product_repository`, `supplier_repository`, `report_service`, `add_expense_screen`) تستخدم بالفعل `await locator<BaseCurrencyService>().getOffsetForCurrency(currency)` بشكل ديناميكي. لم يتبقَ أي استخدام ثابت لـ `codeOffset` خارج fallback التوافقية داخل `BaseCurrencyService` نفسه (للدعم الخلفي v49).
**المهمة:** `B-1.7-P3` — ✅ تلقائياً منجزة مع تطبيق B-1.7 Phase 1/2.

## A-12 ✅ `AppConstants.defaultVatRate` ثابت = 0.0 — **مُصلحة**
**الحالة:** ✅ منجزة (commit `TBD`)
**الوصف:** تم إزالة الثابت `AppConstants.defaultVatRate` بالكامل. تم إضافة `vat_rate` إلى جدول `currencies` (migration v52) وتحديث `schema.dart`. يتم الآن تحميل VAT rate ديناميكياً من قاعدة البيانات حسب العملة المختارة في `InvoiceViewModel` و `PosViewModel`. كما تم تحديث واجهات `create_invoice_screen` و `invoice_summary_section` و `pos_screen` و `add_product_sheet` لاستخدام VAT rate الديناميكي.
**المهمة:** `C-03` (VAT rate configurability)

---

# ⚠️ قسم جديد: أخطاء مهمة (Important Issues)

| # | الوصف | الحالة | الملفات | المهمة |
|---|---|---|---|---|
| I-01 | `MoneyHelper.readMoney()` يُستخدم على `double` من UI (legacy semantic) في `invoice_repository` | ✅ منجزة | `invoice_repository` | `I-01` |
| I-02 | `unit_cost` في `InvoiceItem` لا يُعرض في UI (غير مُقرأ في `fromMap`) | ✅ منجزة | `invoice_item_model`, `add_invoice_item_sheet`, `invoice_viewmodel`, `invoice_item_card`, `create_invoice_screen` | `I-02` |
| I-04 | POS لا يدعم `transport_charges` (غير موجود في `invoiceMap`) | ✅ منجزة | `pos_screen`, `pos_viewmodel`, `pos_totals_section` | `I-04` |
| I-05 | `exchange_rate` و `currency_code` غير مُخزّنين في `transactions` table | ✅ منجزة | `transactions` schema, `migration_v46` | `I-05` |

---

## I-02 ✅ تفعيل `unit_cost` في `InvoiceItem` — تفاصيل الإنجاز
**الحالة:** ✅ منجزة (2026-06-11)
**الوصف:** تم تفعيل حقل `unit_cost` (تكلفة الوحدة) ليكون لقطة تاريخية عند البيع/الشراء بدلاً من الاعتماد على جدول المنتجات فقط.
**الملفات المُعدَّلة:**
- `lib/core/viewmodels/invoice_viewmodel.dart` (سطر ~494): `addItemFromProduct()` تُضبط `unitCost` من `average_cost` أو `cost_price`.
- `lib/ui/screens/invoices/add_invoice_item_sheet.dart` (سطر ~748): تمرير `unitCost:` إلى `InvoiceItem()` عند الإنشاء (شراء: `_unitPrice`، بيع: `averageCost` أو `costPrice`).
- `lib/ui/widgets/invoice_item_card.dart`: عرض صف "تكلفة: X" عندما يكون `item.unitCost > 0`.
- `lib/ui/screens/invoices/create_invoice_screen.dart` (موقعان): إضافة `'unit_cost': item.unitCost` إلى `itemsMaps` في `checkReturnLimits` و `_saveInvoice` لضمان حفظ اللقطة التاريخية.

## I-04 ✅ دعم `transport_charges` في نقطة البيع (POS) — تفاصيل الإنجاز
**الحالة:** ✅ منجزة (2026-06-11)
**الوصف:** أضيفت قدرة POS على احتساب وعرض وحفظ أجور النقل (`transport_charges`) بشكل مماثل لشاشة الفاتورة الاعتيادية.
**الملفات المُعدَّلة:**
- `lib/core/viewmodels/pos_viewmodel.dart`: إضافة `_transportCharges` و `setTransportCharges()` وإدراجها في `total` و `resetForNewInvoice()`.
- `lib/ui/screens/pos/pos_screen.dart`: زر أجور النقل في AppBar، دالة `_showTransportDialog()`، تمرير `transport_charges` في `invoiceMap` و `transportChargesParam` إلى Repository.
- `lib/ui/screens/pos/widgets/pos_totals_section.dart`: إضافة صف عرض `transportCharges`.
- `lib/data/datasources/repositories/invoice_repository.dart`: تم التحقق من دعم `transportChargesParam` (سطر ~95).

---

# 💡 قسم تحسينات (Enhancements)

| # | الوصف | الحالة | المهمة |
|---|---|---|---|
| E-01 | إضافة `currency_code` و `exchange_rate` إلى `transactions` table | ❌ غير منجزة | `E-01` |
| E-02 | إضافة `default_vat_rate` و `default_currency` إلى `settings` table | 🔶 جزئية (migration v52 أضاف `default_vat_rate` إلى settings؛ لا يزال `default_currency` غير موجود في settings ولا يُقرأ منها) | `E-02` |
| E-03 | إزالة `AppConstants.currency` و `AppConstants.currencyEn` (mutable globals) | ✅ منجزة (B-1.7 Phase 2 أزال ~20 استخدام في UI؛ تم إزالة آخر استخدام متبقي في `product_form_helpers.dart` وجعل `currencySymbol` إلزامياً في `ProductPriceField`) | `E-03` |

---
**قاعدة دائمة:** يتم تحديث هذا الملف فور الانتهاء من أي ميزة أو إصلاح قبل الانتقال للمهمة التالية.
