# FirstProAccounting Complete Product Implementation Plan

> **For agentic workers:** نفّذ المهام بالتتابع على `main`، واستخدم دورة TDD لكل سلوك جديد. لا تتجاوز بوابة CI أو تنتقل إلى مهمة لاحقة عند وجود فشل محاسبي أو فشل ترجمة.

**Goal:** إكمال FirstProAccounting كتطبيق Android محاسبي وتشغيلي للتجارة والخدمات والصيانة والمخابز والمعاجن، مع صحة مالية ومخزنية واختبارات CI كاملة.

**Architecture:** الحفاظ على طبقات Flutter الحالية مع Provider/GetIt، ووضع السياسات والمحركات النقية في `lib/core/`، والخدمات المعاملية في `lib/data/datasources/services/`، وواجهات التشغيل في `lib/ui/`. كل عملية مالية أو مخزنية مركبة تُنفذ داخل transaction واحدة، وكل تغيير Schema يمر عبر Migration جديد.

**Tech Stack:** Flutter/Dart 3.3، SQLite/SQLCipher عبر `sqflite_sqlcipher`، Provider، GetIt، Material 3، Flutter localization، GitHub Actions Android Release.

**Spec:** `docs/superpowers/specs/2026-08-18-firstpro-accounting-complete-product-design.md`

## Global Constraints

- العمل على `main` مباشرة وعدم إنشاء worktree.
- عدم تثبيت Flutter أو حزم Flutter محلياً للفحص فقط؛ تحقق البناء النهائي عبر GitHub Actions.
- عدم تعديل migrations من v2 إلى v56؛ كل Schema جديد يبدأ من v58 بعد v57.
- عدم حذف ميزات أو قيود أو قيود محاسبية تاريخية.
- كل مبلغ مالي جديد يخزن كوحدات صغرى صحيحة، ويستخدم `MoneyEngine` و`CurrencyEngine` و`TaxEngine` و`InvoiceTotalsEngine` حسب المجال.
- لا حركة مخزون عند المسودة، ولا COGS للخدمة أو المنتج غير المخزني.
- لا تعديل أو حذف لقيد مرحّل؛ الإلغاء بقيد عكسي جديد مع metadata وسبب ومرجع.
- يجب أن يسبق كود الإنتاج اختبار فاشل، ثم اختبار ناجح، ثم refactor لا يغيّر السلوك.
- بعد كل دفعة مترابطة: `git diff --check`، commit، push، متابعة GitHub Actions، وإصلاح أي فشل باختبار انحدار.

---

### Task 1: تثبيت خط الأساس وخريطة الفجوات

**Files:**
- Read: `AGENTS.md`
- Read: `docs/superpowers/specs/2026-08-18-firstpro-accounting-complete-product-design.md`
- Read: `agent-ctx/AUDIT.md`
- Create/Modify: `/home/ubuntu/worklog.md`
- Test/Inspect: `test/comprehensive_audit_test.dart`, `test/regression/`, `.github/workflows/android-release.yml`

**Interfaces:**
- Consumes: الحالة الحالية على commit `221b849`، وقواعد المشروع في `AGENTS.md`.
- Produces: قائمة فجوات قابلة للتنفيذ مرتبة حسب الخطورة، دون تعديل كود إنتاج.

- [ ] **Step 1: سجل خط الأساس.** نفّذ `git status --short` و`git log -5 --oneline` وسجل commit الرأس في worklog.
- [ ] **Step 2: احصر الخدمات والشاشات والـ routes الحالية.** استخدم `find` و`grep` وحدد ما هو موجود فعلاً للدفعات والضمانات والإنتاج والوحدات والصلاحيات والنسخ الاحتياطي.
- [ ] **Step 3: اربط كل فجوة بملف واختبار وبوابة.** صنّفها Critical/High/Medium/Low وفق AGENTS.md، ولا تضع فجوة بلا أثر قابل للفحص.
- [ ] **Step 4: نفّذ الفحوص المحلية غير المعتمدة على Flutter.** شغّل `git diff --check` وguards المصدر الحالية.
- [ ] **Step 5: Commit.** استخدم `git commit -m "docs: record complete product baseline"` فقط إذا أضيفت معلومات جديدة إلى worklog أو وثائق الفحص.

**Verification:** لا تغيير إنتاجي، مستودع نظيف، وخريطة فجوات محفوظة في worklog أو وثيقة تدقيق.

---

### Task 2: دفعات وضمانات وحدة الخدمات

**Files:**
- Modify: `lib/data/datasources/services/service_order_service.dart`
- Read/Modify: `lib/data/datasources/services/journal_service.dart`, `lib/core/finance/currency_engine.dart`
- Test: `test/integration/service/service_payment_test.dart`
- Test: `test/core/service/service_warranty_test.dart`
- Test: `test/regression/service_order_migration_regression_test.dart`

**Interfaces:**
- Consumes: `ServiceOrderService.recordPayment`, `postPayment`, `addWarranty`, `ServiceOrderTotals`، وقيود v57 الحالية.
- Produces: دفعات غير سالبة لا تتجاوز المتبقي، ترحيل دفعة واحد، وضمان زمني غير مالي.

- [ ] **Step 1: اكتب اختبار RED للدفعة الصفرية والسالبة.** تحقق من `StateError` أو الاستثناء المعتمد في الخدمة، ومن عدم إنشاء صف أو قيد.
- [ ] **Step 2: اكتب اختبار RED للدفعة الأكبر من المتبقي.** أنشئ أمر خدمة مرحلاً بمبلغ معلوم، ثم حاول دفعة تتجاوزه وتحقق من عدم تغير `paid_amount`.
- [ ] **Step 3: اكتب اختبار RED لـ `amount_base`.** استخدم عملة غير أساسية ومعدل صرف معروف، وتحقق من أن القيمة تطابق `CurrencyEngine` بوحدات صغرى.
- [ ] **Step 4: نفّذ التحقق داخل transaction.** أعد تحميل رأس الأمر والبنود، وأعد حساب المتبقي من مصدر الحقيقة قبل إدراج الدفعة.
- [ ] **Step 5: اكتب اختبار RED لمنع ترحيل الدفعة مرتين.** ترحّل payment مرة، ثم تعيد استدعاء `postPayment` وتتحقق من رفض العملية وعدم إضافة قيد ثانٍ.
- [ ] **Step 6: نفّذ القيد عبر JournalService.** لا تعدل رصيد الصندوق أو الحساب مباشرة، واجعل reference type هو `service_payment` مع order/payment identifiers وmetadata الكاملة.
- [ ] **Step 7: اكتب اختبار RED للضمان.** ارفض تاريخ نهاية قبل البداية، وأثبت أن إنشاء الضمان لا ينشئ journal أو stock movement.
- [ ] **Step 8: نفّذ الضمان وسجل حالته.** حافظ على ارتباطه بأمر الخدمة أو الجهاز، وامنع تخزين بيانات حساسة غير محمية.
- [ ] **Step 9: شغّل الاختبارات المرتبطة ثم commit.** استخدم `git commit -m "feat: complete service payments and warranties"`، وادفع إلى `main`.
- [ ] **Step 10: راقب CI.** لا تنتقل قبل نجاح analyze/tests/APK/AAB.

**Verification:** دفعات سليمة محاسبياً، ضمانات تشغيلية بلا أثر مالي، وعدم كسر اختبارات v57 السابقة.

---

### Task 3: واجهات أمر الخدمة والتنقل والصلاحيات

**Files:**
- Create/Modify: `lib/ui/screens/service_orders/service_orders_screen.dart`
- Create/Modify: `lib/ui/screens/service_orders/service_order_form_screen.dart`
- Create/Modify: `lib/ui/screens/service_orders/service_order_details_screen.dart`
- Create/Modify: `lib/core/viewmodels/service_order_viewmodel.dart`
- Modify: `lib/ui/navigation/app_router.dart`
- Modify: `lib/ui/navigation/main_scaffold.dart`
- Modify: `lib/core/di/service_locator.dart`
- Test: `test/unit/viewmodels/service_order_viewmodel_test.dart`
- Test: `test/widget/service_orders/service_orders_screen_test.dart`

**Interfaces:**
- Consumes: `ServiceOrderService` وواجهات العملاء والمنتجات الحالية ونمط `sales_orders_screen.dart`.
- Produces: قائمة، إنشاء/تحرير مسودة، تفاصيل، تغيير حالة، ترحيل، دفعة، إلغاء، وضمان مع صلاحيات واضحة.

- [ ] **Step 1: اكتب ViewModel RED.** اختبر تحميل القائمة، التصفية بالحالة والعميل، وإظهار أخطاء الخدمة دون ابتلاعها.
- [ ] **Step 2: اكتب Widget RED.** تحقق من ظهور زر الترحيل فقط للحالات المسموحة، وإظهار ملخص الخدمات والقطع والضريبة والمتبقي.
- [ ] **Step 3: نفّذ ViewModel.** استخدم Provider/ChangeNotifier، ولا تعِد حساب الإجماليات بعيداً عن `ServiceOrderTotals`.
- [ ] **Step 4: نفّذ الشاشات بنمط Material 3.** حافظ على Cairo وRTL/LTR، واستعمل مكونات الإدخال الحالية وتحقق من الحقول قبل إرسالها.
- [ ] **Step 5: اربط route وdrawer.** أضف route باسم ثابت، وادخل الوحدة في التنقل دون إزالة أي قسم موجود.
- [ ] **Step 6: اربط الحواجز.** اعرض رسائل حالة مفهومة، وامنع الإلغاء/الترحيل/تعديل البيانات المرحّلة وفق السياسة والصلاحية.
- [ ] **Step 7: شغّل اختبارات الوحدة والWidget ثم commit.** استخدم `git commit -m "feat: add service order mobile workflow"`، وادفع إلى `main`.
- [ ] **Step 8: راقب CI.** أصلح أخطاء التحليل أو Widget قبل الانتقال.

**Verification:** يستطيع المستخدم تنفيذ دورة أمر الخدمة من Android، ولا يستطيع تجاوز الحواجز المحاسبية من الواجهة.

---

### Task 4: تعميق اختبارات الخدمات والعملات والضرائب

**Files:**
- Test: `test/acceptance/service_maintenance_acceptance_test.dart`
- Test: `test/integration/service/service_order_posting_test.dart`
- Create/Modify: `test/regression/service_order_financial_regression_test.dart`
- Test/Modify: `test/core/finance/`, `test/accounting/`
- Inspect/Modify: `lib/core/finance/`, `lib/data/datasources/repositories/invoice_repository.dart`

**Interfaces:**
- Consumes: خدمة v57 وInvoiceTotalsEngine وTaxEngine وCurrencyEngine.
- Produces: تغطية مثبتة للخدمة والقطعة والعملة والضريبة والإلغاء والفترة المغلقة.

- [ ] **Step 1: اكتب RED لاختبار خدمة فقط.** تحقق من قيد الذمم/الإيراد، عدم `stock_movements`، عدم COGS، وتوازن journal.
- [ ] **Step 2: اكتب RED لاختبار قطعة متتبعة.** تحقق من نقص `current_stock`، حركة `service_order`، COGS، وتوازن القيود.
- [ ] **Step 3: اكتب RED لاختبار foreign currency.** تحقق من `amount_base`، المعدل، والمبالغ الصحيحة دون floating conversion.
- [ ] **Step 4: اكتب RED لاختبار الضريبة والخصم والنقل.** قارن النتائج بمحرك الإجماليات ولا تعتمد على قيمة مرسلة من UI.
- [ ] **Step 5: اكتب RED لاختبار الفترة المغلقة والتكرار.** تحقق من الرفض قبل أي أثر قاعدة بيانات.
- [ ] **Step 6: أصلح الحواجز أو التنفيذ فقط عند فشل اختبار صحيح.** لا تغير الاختبار لتطابق الكود.
- [ ] **Step 7: شغّل مجموعة الاختبارات الكاملة المتاحة محلياً إن كانت Flutter موجودة، وإلا نفّذ guards محلية وادفع إلى CI.**
- [ ] **Step 8: Commit وCI.** استخدم `git commit -m "test: deepen service financial acceptance coverage"`.

**Verification:** كل مسار خدمة/قطعة/عملة/ضريبة له اختبار يثبت أثره المحاسبي والمخزني.

---

### Task 5: تصميم وترحيل طبقة الإنتاج للمخابز والمعاجن

**Files:**
- Create: `lib/data/datasources/migrations/migration_v58.dart`
- Modify: `lib/data/datasources/migrations/schema.dart`
- Create: `lib/data/models/recipe_model.dart`
- Create: `lib/data/models/recipe_line_model.dart`
- Create: `lib/data/models/production_order_model.dart`
- Create: `lib/data/models/production_consumption_model.dart`
- Create: `lib/data/models/production_output_model.dart`
- Create: `lib/core/production/recipe_policy.dart`
- Create: `lib/core/production/production_totals.dart`
- Modify: database migration runner and `lib/core/di/service_locator.dart`
- Test: `test/regression/production_migration_regression_test.dart`
- Test: `test/core/production/recipe_policy_test.dart`

**Interfaces:**
- Consumes: `ProductKind`, product/account identifiers، `StockService` و`CostingEngineService`.
- Produces: جداول ووحدات وصفة وإنتاج قابلة للترحيل، مع رفض الدورات والكميات غير الصحيحة.

- [ ] **Step 1: اكتب RED لسياسة الوصفة.** ارفض مكوناً غير مخزني، كمية صفرية/سالبة، وصفة دائرية، أو منتج ناتج غير مخزني.
- [ ] **Step 2: اكتب RED لاختبار migration.** افتح قاعدة v57 واثبت إنشاء جداول v58 والفهارس والقيم الافتراضية دون تعديل البيانات القديمة.
- [ ] **Step 3: صمّم الجداول.** استخدم `recipes`, `recipe_lines`, `production_orders`, `production_consumptions`, `production_outputs`, و`production_status_history` مع IDs وaudit fields وforeign keys المناسبة.
- [ ] **Step 4: نفّذ Migration v58.** أضفها إلى runner، واستخدم `CREATE TABLE IF NOT EXISTS` وindexes للمراجع والحالة والمنتج.
- [ ] **Step 5: اكتب اختبارات النماذج والسياسات.** تحقق من parse/serialize والوحدات الصغرى وحالة الأمر.
- [ ] **Step 6: نفّذ النماذج والمحركات النقية.** اجعل الوصفة خطية في أول إصدار، وامنع أي cycle قبل الحفظ.
- [ ] **Step 7: شغّل اختبارات migration والسياسات ثم commit.** استخدم `git commit -m "feat: add production recipe schema"`، وادفع إلى `main`.
- [ ] **Step 8: راقب CI قبل بناء خدمة الإنتاج.**

**Verification:** قاعدة v57 تترقى إلى v58 دون فقد، والوصفات غير الصالحة تُرفض قبل أي حركة.

---

### Task 6: تنفيذ ترحيل الإنتاج والتكلفة والهالك

**Files:**
- Create: `lib/data/datasources/services/production_service.dart`
- Modify: `lib/data/datasources/services/stock_service.dart`
- Modify: `lib/data/datasources/services/costing_engine_service.dart`
- Modify: `lib/data/datasources/services/journal_service.dart` only for shared safe helper if required
- Test: `test/unit/services/production_service_test.dart`
- Test: `test/integration/production/production_posting_test.dart`
- Test: `test/regression/production_reversal_regression_test.dart`

**Interfaces:**
- Consumes: `RecipePolicy`, stock/costing/journal services، والفترة والعملة الأساسية.
- Produces: `createDraft`, `addLine`, `postProduction`, `cancelProduction` أو الواجهات المكافئة، مع حركات خامات ومنتج تام وهالك وقيد متوازن.

- [ ] **Step 1: اكتب RED للترحيل الناجح.** أنشئ وصفة ودraft، ثم تحقق من استهلاك الخام وزيادة المنتج التام وتسجيل المراجع.
- [ ] **Step 2: اكتب RED لمنع نقص المخزون.** تحقق من rollback كامل: لا كمية ولا حركة ولا journal عند الرفض.
- [ ] **Step 3: اكتب RED لتكلفة الإنتاج والهالك.** تحقق من تكلفة الوحدات الصحيحة وقيد المخزون/الإنتاج أو الهالك وفق الحسابات المزروعة.
- [ ] **Step 4: اكتب RED لمنع الترحيل المكرر والإلغاء غير الآمن.** تحقق من قيد عكسي جديد وحفظ الأصل.
- [ ] **Step 5: نفّذ transaction واحدة.** احصل على offsets خارج transaction، ثم تحقق من الحالة والفترة، وأعد حساب المواد والتكلفة داخلها.
- [ ] **Step 6: نفّذ حركات الخام والتام والهالك بمرجع `production_order`.** لا تعدل `current_stock` خارج StockService.
- [ ] **Step 7: نفّذ القيود المتوازنة بالعملة الأساسية وبmetadata كاملة.** لا تستخدم إدراج journal ديناميكي غير قابل للحراسة المصدرية.
- [ ] **Step 8: شغّل unit/integration/regression ثم commit.** استخدم `git commit -m "feat: post production orders with costing"`، وادفع وراقب CI.

**Verification:** إنتاج مخبز كامل من الوصفة إلى المخزون والتكلفة والتراجع، دون أثر جزئي.

---

### Task 7: مراجعة المخزون والوحدات التجارية والتسويات

**Files:**
- Inspect/Modify: `lib/data/models/product_model.dart`
- Inspect/Modify: `lib/data/datasources/services/stock_service.dart`
- Inspect/Modify: `lib/data/datasources/repositories/invoice_repository.dart`
- Create/Modify: `lib/core/inventory/unit_conversion_policy.dart`
- Create/Modify: `lib/data/datasources/services/inventory_adjustment_service.dart`
- Test: `test/core/inventory/unit_conversion_policy_test.dart`
- Test: `test/integration/inventory/inventory_adjustment_test.dart`
- Test: `test/regression/inventory_negative_stock_regression_test.dart`

**Interfaces:**
- Consumes: ProductKind، المخازن والحركات الحالية، ومحركات التكلفة.
- Produces: تحويل وحدات آمن، جرد وتسوية قابلة للتدقيق، وحاجز سالب واضح.

- [ ] **Step 1: اكتب RED للتحويل.** تحقق من تحويل كمية أساسية إلى وحدة بيع والعكس دون فقد دقة، وارفض عامل صفر أو سالب.
- [ ] **Step 2: اكتب RED للتسوية.** تحقق من أن الفرق يولد حركة وقيداً مناسباً مع سبب ومستخدم، ولا يعدل التاريخ الأصلي.
- [ ] **Step 3: اكتب RED للسالب.** تحقق من رفض الخصم فوق المتاح للأصناف المتتبعة بالتكلفة، مع بقاء قاعدة البيانات كما كانت.
- [ ] **Step 4: راجع الحواجز لكل ProductKind.** ثبّت أن service/nonStock لا يتحركان، وأن stock/bundle يتبعان السياسة.
- [ ] **Step 5: نفّذ policy/service مركزيين.** استخدم transaction واحدة وحسابات تكلفة صحيحة، وأضف indexes للمسارات الحرجة عند الحاجة عبر Migration v59.
- [ ] **Step 6: شغّل اختبارات المخزون القائمة والجديدة ثم commit.** استخدم `git commit -m "feat: harden inventory units and adjustments"`، ثم CI.

**Verification:** المبيعات والخدمات والإنتاج والتسويات تستخدم مسار مخزون واحداً، ولا يوجد اختلاف صامت بين الكمية والقيود.

---

### Task 8: مراجعة الضرائب والعملات والفترات والإلغاءات

**Files:**
- Inspect/Modify: `lib/core/finance/tax_engine.dart`
- Inspect/Modify: `lib/core/finance/currency_engine.dart`
- Inspect/Modify: `lib/core/finance/invoice_totals_engine.dart`
- Inspect/Modify: `lib/data/datasources/services/fiscal_period_service.dart`
- Inspect/Modify: invoice/purchase/expense/service/production posting services
- Test: `test/core/finance/`, `test/regression/tax_currency_period_regression_test.dart`
- Test: `test/integration/accounting/reversal_integrity_test.dart`

**Interfaces:**
- Consumes: جميع المستندات المرحّلة ومحركات النواة المالية.
- Produces: تطبيق موحد للضريبة والعملات والفترات والعكس في كل المسارات.

- [ ] **Step 1: اكتب RED لتقريب الضريبة.** اختبر exclusive/inclusive والنقاط الأساسية والحالات الحدية.
- [ ] **Step 2: اكتب RED للتحويل.** اختبر amount base والكسور ومعدل صرف صفر/سالب وعدم استخدام double في التخزين.
- [ ] **Step 3: اكتب RED للفترة المغلقة.** اختبر كل خدمة ترحيل رئيسية قبل إدراج أي journal أو stock movement.
- [ ] **Step 4: اكتب RED للإلغاء في فترة لاحقة.** تحقق من reversal جديد ومرجع وسبب، دون حذف الأصل.
- [ ] **Step 5: افحص كل مسار مالي بالبحث النصي.** حدد أي حسابات أو إجماليات أو تحويلات مكررة، ثم اكتب regression قبل الإصلاح.
- [ ] **Step 6: وحّد المسارات بمحركات النواة.** أزل الحسابات المتكررة فقط عندما يثبت الاختبار عدم تغير السلوك الصحيح.
- [ ] **Step 7: شغّل كل اختبارات المحاسبة ثم commit.** استخدم `git commit -m "fix: unify tax currency and fiscal posting rules"`، وراقب CI.

**Verification:** كل مستند مالي يستخدم قواعد واحدة، والأثر المالي للفترة والعملة والضريبة قابل للتدقيق.

---

### Task 9: التقارير ودفتر الأستاذ والتدقيق والصلاحيات

**Files:**
- Inspect/Modify: `lib/data/datasources/services/report_service.dart`
- Inspect/Modify: `lib/data/datasources/services/audit_service.dart`
- Inspect/Modify: `lib/ui/screens/reports/`
- Inspect/Modify: `lib/core/security/`
- Inspect/Modify: `lib/data/datasources/services/permission_service.dart` أو موضع الصلاحيات الحالي
- Test: `test/integration/reports/report_ledger_consistency_test.dart`
- Test: `test/integration/audit/audit_trail_integrity_test.dart`
- Test: `test/unit/security/permission_policy_test.dart`

**Interfaces:**
- Consumes: journals، stock movements، service/production references، ومستخدم التطبيق.
- Produces: تقارير مشتقة من الأثر الفعلي، وسجل تدقيق، وحواجز صلاحية للعمليات الحساسة.

- [ ] **Step 1: اكتب RED لمقارنة دفتر الأستاذ.** أدخل قيوداً معروفة، ثم قارِن التقرير بمجموع المدين والدائن والأرصدة.
- [ ] **Step 2: اكتب RED لتقارير المخزون وCOGS.** تحقق من تطابق الحركة والتكلفة مع النتائج المالية.
- [ ] **Step 3: اكتب RED لسجل التدقيق.** تحقق من المرجع والمستخدم والتاريخ والسبب وعدم قابلية السجل للحذف من مسار UI.
- [ ] **Step 4: اكتب RED للصلاحيات.** امنع الترحيل والإلغاء والتسوية والإنتاج وتعديل الإعدادات للمستخدم غير المصرح.
- [ ] **Step 5: أصلح مصادر التقارير لا واجهة العرض فقط.** اجعل الاستعلامات تعكس journals وmovements الفعلية وتراعي العملة والفترة.
- [ ] **Step 6: اربط الصلاحيات برسائل UI واضحة.** لا تعتمد على إخفاء الزر وحده؛ تحقق في الخدمة أيضاً.
- [ ] **Step 7: شغّل اختبارات التقارير والأمن ثم commit.** استخدم `git commit -m "feat: strengthen accounting reports audit and permissions"`، وراقب CI.

**Verification:** الأرقام المعروضة يمكن تتبعها إلى قيد أو حركة، والعمليات الحساسة محمية من الواجهة والخدمة.

---

### Task 10: واجهات الإنتاج والمخزون والتشغيل التجاري

**Files:**
- Create/Modify: `lib/ui/screens/production/`
- Create/Modify: `lib/ui/screens/inventory_adjustments/`
- Modify: `lib/ui/navigation/app_router.dart`
- Modify: `lib/ui/navigation/main_scaffold.dart`
- Modify: localization ARB/generated localization sources
- Test: `test/widget/production/production_screen_test.dart`
- Test: `test/widget/inventory/inventory_adjustment_screen_test.dart`

**Interfaces:**
- Consumes: `ProductionService`, `InventoryAdjustmentService`, policy/viewmodel patterns الحالية.
- Produces: تدفقات تشغيل للمخبز والجرد والتسوية دون كشف تفاصيل محاسبية خطرة للمستخدم.

- [ ] **Step 1: اكتب Widget RED للتعريف بالوصفة وأمر الإنتاج.** تحقق من إدخال المنتج والمكونات والكميات ورسائل validation.
- [ ] **Step 2: اكتب Widget RED للتسوية والجرد.** تحقق من السبب والكمية والتأكيد قبل أثر مالي.
- [ ] **Step 3: نفّذ ViewModels والشاشات.** افصل حالة الإدخال عن service، وأظهر preview للتكلفة والنتيجة قبل الاعتماد.
- [ ] **Step 4: اربط التنقل والترجمة.** أضف النصوص إلى ARB، واحترم RTL/LTR ولا تضع نصوصاً صلبة في الكود.
- [ ] **Step 5: شغّل Widget/acceptance ثم commit.** استخدم `git commit -m "feat: add production and inventory operation screens"`، ثم CI.

**Verification:** أصحاب المخابز والتجارة يستطيعون تنفيذ العمليات الأساسية من Android دون تجاوز سياسات الخدمة.

---

### Task 11: الترحيل والانحدار والنسخ الاحتياطي وتحسين Android

**Files:**
- Inspect/Modify: `lib/data/datasources/migrations/`
- Inspect/Modify: backup/restore services in `lib/data/datasources/services/`
- Inspect/Modify: `lib/core/security/`, `lib/ui/screens/app_lock/`
- Inspect: `android/`, `.github/workflows/android-release.yml`
- Test: `test/database/`
- Test: `test/regression/full_upgrade_regression_test.dart`
- Test: `test/integration/backup_restore_test.dart`

**Interfaces:**
- Consumes: migrations حتى آخر إصدار، SQLCipher، إعدادات Android، ونظام القفل الحالي.
- Produces: ترقية آمنة، نسخ احتياطي/استعادة قابلة للتحقق، وحزمة Android قابلة للتسليم.

- [ ] **Step 1: اكتب RED لكل انتقال Schema جديد.** اختبر قاعدة فارغة وقاعدة v57 وقاعدة تحتوي بيانات نموذجية.
- [ ] **Step 2: اكتب RED للنسخ والاستعادة.** تحقق من استعادة journals/products/customers والـ schema version، ورفض ملف تالف أو غير مصادق.
- [ ] **Step 3: اكتب RED لقفل التطبيق والبيانات الحساسة.** تحقق من عدم عرض محتوى قبل الفتح وعدم تخزين أسرار الأجهزة بصيغة مكشوفة.
- [ ] **Step 4: افحص إعدادات Android والأذونات.** لا تغيّر min/target SDK أو التوقيع دون دليل من المشروع ونجاح CI.
- [ ] **Step 5: أصلح الأداء بالقياس.** أضف indexes واستعلامات محددة فقط عند وجود اختبار أو قياس يبرر التغيير.
- [ ] **Step 6: شغّل regression/database والـ guards ثم commit.** استخدم `git commit -m "test: harden upgrades backup and Android readiness"`، وراقب CI.

**Verification:** قواعد الإصدارات السابقة لا تفقد البيانات، والنسخ الاحتياطي قابل للاستعادة، وحزمة Android تبنى وتوقع.

---

### Task 12: القبول النهائي والتوثيق والتسليم

**Files:**
- Modify: `test/acceptance/`
- Create/Modify: `docs/complete-product-acceptance-ar.md`
- Modify: `AGENTS.md`
- Modify: `/home/ubuntu/worklog.md`
- Modify: `agent-ctx/AUDIT.md`

**Interfaces:**
- Consumes: كل الوحدات والاختبارات والـ CI runs السابقة.
- Produces: تقرير قبول نهائي صادق، ومصفوفة متطلبات/اختبارات، وحالة تسليم واضحة.

- [ ] **Step 1: اكتب سيناريو تاجر تجارة عامة.** شراء، بيع، مرتجع، مخزون، COGS، ضريبة، تقرير.
- [ ] **Step 2: اكتب سيناريو محل صيانة.** أمر خدمة، جهاز، خدمة، قطعة، دفعة، ضمان، تسليم، إلغاء.
- [ ] **Step 3: اكتب سيناريو مخبز.** وصفة، إنتاج، خامات، تام، هالك، تكلفة، تقرير مخزون.
- [ ] **Step 4: اكتب سيناريو عملة وفترة وصلاحية.** تحقق من الرفض والأثر الصحيح.
- [ ] **Step 5: شغّل `git diff --check`، ثم كل الاختبارات عبر GitHub Actions.** استخرج status/conclusion واحتفظ بالأرقام.
- [ ] **Step 6: راجع التقرير بحثاً عن ادعاء غير مثبت.** كل نجاح يجب أن يرتبط باختبار أو CI run، وكل تحذير يجب أن يذكر صراحة.
- [ ] **Step 7: حدّث AGENTS وAUDIT وworklog.** سجل آخر commit، عدد الاختبارات إن ظهر في CI، وبناء APK/AAB.
- [ ] **Step 8: Commit نهائي.** استخدم `git commit -m "docs: finalize complete product acceptance"`، وادفع إلى `main`.
- [ ] **Step 9: راقب التشغيل الأخير حتى `completed/success`.** لا تسلّم قبل نجاح التحليل والاختبارات والبناء.

**Verification:** مصفوفة قبول تغطي التجارة والخدمات والصيانة والمخبز، وCI النهائي ناجح، والفرع نظيف ومتزامن مع `origin/main`.

---

## بوابات الانتقال

لا تبدأ Task 3 قبل نجاح Task 2. لا تبدأ Task 5 قبل نجاح واجهات الخدمات واختبارات الخدمات. لا تبدأ Task 6 قبل نجاح Migration v58. لا تبدأ Task 7 قبل إثبات صحة الإنتاج أو فصل مسار الإنتاج عن المخزون العادي. لا تبدأ Task 8 قبل وجود اختبارات ممثلة لكل مسار مالي. لا تبدأ Task 12 قبل نجاح Android CI في Task 11.

## أوامر التحقق القياسية

```bash
git diff --check
git status --short
git log -1 --oneline
gh run list --repo Nagmix/FirstProAccounting --limit 5
gh run view <RUN_ID> --repo Nagmix/FirstProAccounting --json status,conclusion,headSha
```

لأن Flutter غير متوفر محلياً، تكون أوامر `flutter analyze`, `flutter test`, `flutter build apk`, و`flutter build appbundle` ضمن GitHub Actions فقط، ولا يُدّعى نجاحها إلا من سجل CI.
