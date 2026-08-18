# خطة تنفيذ النواة المحاسبية والوحدات التجارية — FirstProAccounting

> **للمهندسين المنفذين:** تُنفذ المهام بالترتيب، وكل مهمة لا تُعتبر مكتملة حتى تنجح اختبارات الوحدة والاختبارات المحاسبية المرتبطة بها. لا يُسمح بإضافة شاشة جديدة فوق مسار مالي لم تثبت صحته.

**الهدف:** تحويل FirstProAccounting إلى تطبيق Android محاسبي ومخزني آمن للتجار والمحلات الصغيرة، مع أتمتة القيود والتكلفة والضرائب والعملات والفترات، وإضافة دعم أصلي للتجارة والخدمات وصيانة الهواتف والمخابز والتصنيع الخفيف دون حذف صامت أو قيود غير متوازنة.

**المعمارية:** تُبنى النواة حول محركات مركزية قابلة للاختبار: `MoneyEngine` للنقود والتقريب، `TaxEngine` للضريبة، `PostingEngine` للقيود، `InventoryCostEngine` للكمية والتكلفة، و`PeriodGuard` للفترات. تتعامل الفواتير وPOS والجرد والتحويل وأوامر الخدمة والإنتاج مع هذه المحركات بدل إعادة الحساب داخل كل ViewModel أو Repository. يبقى SQLite/SQLCipher مخزنًا محليًا، وتنفذ العمليات المالية داخل معاملات قاعدة بيانات ذرية مع سجل تدقيق وروابط مصدرية.

**التقنيات:** Flutter/Dart، SQLite/SQLCipher، طبقة Repository/Service/ViewModel الحالية، GitHub Actions، اختبارات Dart/Flutter، ومخطط ترحيل قاعدة البيانات بإصدارات متتابعة.

**المواصفة المرجعية:** `FirstProAccounting_FINANCIAL_OPERATIONAL_AUDIT_AR.md` و`firstpro_target_product_plan_ar.md`.

## القيود العامة

| القيد | القرار الإلزامي |
|---|---|
| المستند المرحّل | لا يُحذف فعليًا؛ يُلغى أو يُعكس بقيد مرتبط |
| القيد | يجب أن يكون متوازنًا في العملة الأصلية والأساسية ضمن سياسة التقريب |
| العملة | يحفظ سعر الصرف والقيمة الأساسية وقت الترحيل ولا يعاد حسابهما بسعر اليوم |
| المخزون | كل حركة كمية وقيمة ترتبط بمصدر ومستودع وصنف وحركة أصلية |
| التكلفة | لا يوجد fallback صامت عند البيع دون طبقة تكلفة؛ إما منع أو حالة معلقة ظاهرة |
| الضريبة | تحسب مركزيًا وتُحفظ نتيجة الحساب على سطر المستند والقيد |
| الفترات | يمنع الترحيل والتعديل والإلغاء في الفترة المغلقة على مستوى الخدمة وقاعدة البيانات |
| الأنشطة | يختار المستخدم نوع النشاط، ولا تظهر الوحدات المتخصصة إلا عند تفعيلها |
| الأمان | لا تُسجل كلمات مرور الأجهزة أو بيانات حساسة في سجل الصيانة دون سياسة صريحة |
| الاختبار | كل تغيير في النواة المالية يسبقه اختبار فاشل ثم تنفيذ ثم اختبار ناجح |
| التوافق | لا تُكسر بيانات الإصدارات السابقة؛ كل تغيير مخطط يملك migration وrollback/backup strategy |

---

## خارطة الملفات قبل التنفيذ

| المسار | المسؤولية بعد الخطة |
|---|---|
| `lib/core/finance/money_engine.dart` | الحساب الدقيق، التقريب، التحويل إلى أصغر وحدة نقدية |
| `lib/core/finance/tax_engine.dart` | الضريبة الشاملة/غير الشاملة، الوعاء، الخصم، قواعد السريان |
| `lib/core/finance/period_guard.dart` | فحص فتح الفترة وتاريخ المستند والعكس |
| `lib/core/finance/posting_engine.dart` | إنشاء قيد متوازن، المصدر، العكس، الأثر التدقيقي |
| `lib/core/finance/posting_models.dart` | نماذج طلب الترحيل ونتيجته وأخطاء التحقق |
| `lib/data/datasources/services/journal_service.dart` | التخزين والتحديث الذري للقيود بعد تفويض التحقق للمحرك |
| `lib/data/datasources/repositories/invoice_repository.dart` | حفظ المستند واستدعاء المحركات دون حسابات محاسبية مستقلة |
| `lib/data/datasources/services/stock_service.dart` | حركات الكمية والقيمة والجرد والتحويل والعكس المرتبط |
| `lib/data/datasources/services/costing_engine_service.dart` | طبقات التكلفة، المتوسط، FIFO، وحالات النقص |
| `lib/data/models/product_model.dart` | نوع الصنف والوحدات والسياسات الأساسية |
| `lib/data/models/inventory_cost_layer_model.dart` | طبقة تكلفة قابلة للتتبع بمصدرها ومستودعها |
| `lib/data/datasources/migrations/schema.dart` | الإصدار الجديد للجداول والفهارس والقيود |
| `lib/data/datasources/migrations/migration_v55_to_v56.dart` | ترحيل النواة المالية الأول |
| `lib/data/datasources/services/service_order_service.dart` | دورة أمر الخدمة والصيانة |
| `lib/data/datasources/services/production_service.dart` | الوصفات والإنتاج والاستهلاك والهدر |
| `lib/data/models/service_order_model.dart` | نموذج أمر العمل والجهاز والبنود والحالات |
| `lib/data/models/recipe_model.dart` | نموذج الوصفة والمكونات والإصدار |
| `test/core/finance/*` | اختبارات المحركات المالية |
| `test/data/services/*` | اختبارات الخدمات والتدفقات الذرية |
| `test/golden/accounting_scenarios/*` | سيناريوهات مالية ثابتة للانحدار |

---

# المرحلة P0: حماية النواة المالية

## المهمة 1: إنشاء دفتر نتائج التدقيق والسيناريوهات المرجعية

**الملفات:**

- إنشاء: `test/golden/accounting_scenarios/accounting_scenarios.dart`
- إنشاء: `test/golden/accounting_scenarios/scenario_assertions.dart`
- إنشاء: `docs/accounting_rules_ar.md`
- تعديل: `README.md` بإضافة نطاق الإصدار وقيود الإطلاق

**الواجهات:** ينتج الملف `AccountingScenario` و`ScenarioResult` وقواعد تحقق موحدة تستخدمها المهام التالية.

- [ ] تعريف سيناريو بيع مخزني نقدي، بيع خدمة، شراء آجل، مرتجع جزئي، جرد، تحويل، عملة، إلغاء، إنتاج، وأمر صيانة.
- [ ] تعريف assertion يثبت أن مجموع المدين يساوي مجموع الدائن، وأن كل transaction يملك `journal_id` ومصدرًا، وأن الكمية والقيمة تتوافقان.
- [ ] كتابة الاختبارات وهي تفشل عند غياب المحركات الجديدة.
- [ ] تسجيل قاعدة أن الخدمة لا تغير المخزون، وأن القطعة تغير المخزون وتولد COGS، وأن التحويل لا يغير إجمالي قيمة المخزون.
- [ ] اعتماد هذه السيناريوهات كمرجع غير قابل للتغيير إلا بمراجعة محاسبية موثقة.

## المهمة 2: محرك النقود والدقة

**الملفات:**

- إنشاء: `lib/core/finance/money_engine.dart`
- إنشاء: `lib/core/finance/money_value.dart`
- تعديل: `lib/core/utils/money_helper.dart`
- اختبار: `test/core/finance/money_engine_test.dart`

**الواجهة الأساسية:**

```dart
class MoneyValue {
  final int minorUnits;
  final String currencyCode;
  const MoneyValue(this.minorUnits, this.currencyCode);
}

class MoneyEngine {
  MoneyValue multiply({required MoneyValue unitPrice, required int quantityScaled, required int scale});
  MoneyValue round(MoneyValue value, RoundingMode mode);
  MoneyValue convert(MoneyValue value, {required DecimalRate rate, required String targetCurrency});
  void assertSameCurrency(MoneyValue left, MoneyValue right);
}
```

- [ ] تخزين القيم المالية بوحدة صحيحة أو Decimal محدد، وعدم استخدام `double` في نتيجة قيد أو تكلفة.
- [ ] تعريف سياسة التقريب مرة واحدة، مع اختبارات 0.005، 1.005، كميات عشرية، وضريبة شاملة.
- [ ] جعل `MoneyHelper.toCents` يستدعي المحرك بدل الحساب المحلي.
- [ ] منع خلط العملة الأصلية بالقيمة الأساسية عبر `MoneyValue` و`DecimalRate`.
- [ ] تشغيل اختبارات التقريب والضرب والتحويل قبل تعديل مسارات الفواتير.

## المهمة 3: نماذج القيد ومحرك الترحيل

**الملفات:**

- إنشاء: `lib/core/finance/posting_models.dart`
- إنشاء: `lib/core/finance/posting_engine.dart`
- تعديل: `lib/data/datasources/services/journal_service.dart`
- تعديل: `lib/data/datasources/migrations/schema.dart`
- إنشاء: `lib/data/datasources/migrations/migration_v55_to_v56.dart`
- اختبار: `test/core/finance/posting_engine_test.dart`

**الواجهة الأساسية:**

```dart
class PostingLine {
  final String accountId;
  final MoneyValue debit;
  final MoneyValue credit;
  final MoneyValue baseDebit;
  final MoneyValue baseCredit;
}

class PostingRequest {
  final String sourceType;
  final String sourceId;
  final DateTime documentDate;
  final String currencyCode;
  final DecimalRate exchangeRate;
  final List<PostingLine> lines;
  final String description;
}

class PostingEngine {
  Future<String> post(DatabaseExecutor txn, PostingRequest request);
  Future<String> reverse(DatabaseExecutor txn, {required String journalId, required DateTime reversalDate, required String reason});
  Future<void> validateBalanced(PostingRequest request);
}
```

- [ ] إضافة حقول `source_type`, `source_id`, `reversal_of_journal_id`, `document_date`, `posting_date`, `original_exchange_rate`, `base_amount`، و`status` إلى القيود والحركات بعد مراجعة أسماء الأعمدة الموجودة.
- [ ] إنشاء قيد واحد متوازن داخل transaction، مع رفض السجل إذا كان المدين لا يساوي الدائن في العملة الأصلية أو الأساسية.
- [ ] جعل العكس يستخدم القيد الأصلي وقيمه المخزنة، لا سعر الصرف الحالي ولا البحث النصي في الوصف.
- [ ] إضافة unique index يمنع إنشاء عكسين لنفس المستند إلا إذا كان النوع يسمح بعكس متعدد مصرحًا به.
- [ ] تعديل `invoice_repository.dart` و`stock_service.dart` لاستدعاء `PostingEngine` بدل إدراج `transactions` في مسارات متفرقة.
- [ ] اختبار فشل الترحيل بالكامل إذا فشل إدراج سطر واحد أو تحديث الرصيد.

## المهمة 4: منع الحذف والتحكم في الفترات

**الملفات:**

- إنشاء: `lib/core/finance/period_guard.dart`
- تعديل: `lib/data/datasources/services/stock_service.dart`
- تعديل: `lib/data/datasources/repositories/invoice_repository.dart`
- تعديل: كل Repository ينفذ حذفًا لمستند مرحّل
- اختبار: `test/core/finance/period_guard_test.dart`

**الواجهة الأساسية:**

```dart
class PeriodGuard {
  Future<void> assertCanPost(DatabaseExecutor txn, DateTime documentDate);
  Future<void> assertCanReverse(DatabaseExecutor txn, DateTime originalDate, DateTime reversalDate);
  Future<void> assertCanEdit(DatabaseExecutor txn, String sourceType, String sourceId);
}
```

- [ ] منع delete المباشر للفواتير والمرتجعات وسندات الجرد والتحويل بعد الترحيل.
- [ ] تحويل الإلغاء إلى `reverse` مع سبب ومستخدم وتاريخ، وتغيير حالة المستند إلى `cancelled`.
- [ ] استخدام تاريخ المستند في فحص الفترة، وتاريخ العكس في فحص الفترة المفتوحة للعكس.
- [ ] إضافة اختبار إلغاء مستند في فترة مغلقة، وتعديل مستند مرحّل، ومحاولة العكس المكرر.

**بوابة P0:** لا تنتقل الخطة إلى P1 حتى تنجح سيناريوهات القيد، العكس، العملة، الفترة، والفشل الذري.

---

# المرحلة P0.5: الضريبة والعملات والتكلفة

## المهمة 5: محرك الضريبة والخصم

**الملفات:**

- إنشاء: `lib/core/finance/tax_engine.dart`
- إنشاء: `lib/core/finance/tax_models.dart`
- تعديل: `lib/core/viewmodels/invoice_viewmodel.dart`
- تعديل: `lib/core/viewmodels/pos_viewmodel.dart`
- تعديل: `lib/data/datasources/repositories/invoice_repository.dart`
- اختبار: `test/core/finance/tax_engine_test.dart`

**الواجهة الأساسية:**

```dart
class TaxCalculation {
  final MoneyValue taxableAmount;
  final MoneyValue discountAmount;
  final MoneyValue taxAmount;
  final MoneyValue totalAmount;
}

class TaxEngine {
  TaxCalculation calculateLine({required MoneyValue price, required int quantityScaled, required TaxRule rule, required DiscountRule discount});
  TaxCalculation calculateDocument(List<TaxLineInput> lines, DocumentTaxContext context);
}
```

- [ ] تحديد صراحة هل السعر شامل للضريبة أو غير شامل، وعدم استنتاج ذلك من الشاشة.
- [ ] تطبيق الخصم على الوعاء حسب إعداد النشاط/الدولة وتخزين الوعاء والضريبة النهائية في السطر.
- [ ] جعل فاتورة البيع وPOS والاقتباس وأمر البيع والمرتجع تستدعي نفس المحرك.
- [ ] فصل ضريبة المبيعات عن ضريبة المشتريات، وإضافة قواعد الإعفاء والنسبة الصفرية دون افتراض دولة معينة.
- [ ] اختبار الضريبة الشاملة، الخصم قبل الضريبة، المرتجع الجزئي، والنقل الخاضع وغير الخاضع.

## المهمة 6: العملة وإعادة التقييم

**الملفات:**

- تعديل: `lib/data/datasources/services/journal_service.dart`
- تعديل: `lib/core/viewmodels/currency_exchange_viewmodel.dart`
- إنشاء: `lib/core/finance/exchange_revaluation_service.dart`
- اختبار: `test/core/finance/exchange_revaluation_test.dart`

- [ ] حفظ سعر الصرف في المستند والقيد والذمة وقت الترحيل.
- [ ] فصل الرصيد الأصلي عن الرصيد الأساسي، وعدم تعديل قيمة المستند التاريخي بعد إدخال سعر جديد.
- [ ] جعل إعادة التقييم عملية مستقلة تولد قيد فروق عملة مرتبطًا بتاريخ التقييم والحساب.
- [ ] اختبار بيع آجل بعملة أجنبية، تحصيل جزئي بسعر مختلف، إعادة تقييم، ثم عكس.

## المهمة 7: محرك طبقات التكلفة والمخزون

**الملفات:**

- تعديل: `lib/data/datasources/services/costing_engine_service.dart`
- تعديل: `lib/data/datasources/services/stock_service.dart`
- تعديل: `lib/data/models/inventory_cost_layer_model.dart`
- إنشاء: `lib/core/inventory/inventory_cost_result.dart`
- اختبار: `test/data/services/costing_engine_service_test.dart`

- [ ] جعل كل حركة تكلفة تحمل `source_type`, `source_id`, `warehouse_id`, `item_id`, `quantity`, `unit_cost`, `total_cost`.
- [ ] تثبيت سياسة cost method لكل صنف أو نشاط مع منع تغييرها دون عملية إعادة تقييم موثقة.
- [ ] منع fallback الصامت عند عدم وجود طبقة؛ إما رفض البيع أو تسجيل نقص تكلفة ظاهر قابل للتسوية.
- [ ] ربط COGS بالطبقات الفعلية المستخدمة في البيع والمرتجع.
- [ ] جعل التحويل بين المستودعات ينقل الطبقة أو قيمة التكلفة نفسها ولا يخلق ربحًا.
- [ ] اختبار FIFO والمتوسط وتعدد المستودعات والبيع تحت الصفر والمرتجع بعد مشتريات متعددة.

**بوابة P0.5:** لا تنتقل الخطة إلى وحدات النشاط حتى تتطابق قيمة المخزون التحليلية مع حساب المخزون، وتطابق COGS مع الطبقات في كل سيناريو.

---

# المرحلة P1: نموذج الأصناف والتجارة

## المهمة 8: فصل الصنف عن الرصيد وتوحيد أنواع العناصر

**الملفات:**

- تعديل: `lib/data/models/product_model.dart`
- تعديل: `lib/data/datasources/repositories/product_repository.dart`
- تعديل: `lib/data/datasources/migrations/schema.dart`
- إنشاء: `lib/data/datasources/migrations/migration_v56_to_v57.dart`
- اختبار: `test/data/repositories/product_repository_test.dart`

- [ ] إضافة `item_type`: `stock`, `service`, `non_stock`, `bundle`, `manufactured`.
- [ ] نقل الكمية والتكلفة وإعادة الطلب من بطاقة الصنف إلى رصيد مستودع `(item_id, warehouse_id)`.
- [ ] منع إنشاء نسخة صنف جديدة أثناء التحويل إذا كان الصنف موجودًا؛ استخدم معرف الصنف نفسه.
- [ ] جعل الخدمة تملك حساب إيراد افتراضيًا ولا تسجل حركة مخزون تلقائيًا.
- [ ] جعل الصنف المخزني يحتاج وحدة أساسية وحساب مخزون وتكلفة، مع رسائل تحقق واضحة.

## المهمة 9: الوحدات والدفعات والسيريالات

**الملفات:**

- إنشاء: `lib/data/models/item_unit_model.dart`
- إنشاء: `lib/data/models/batch_model.dart`
- إنشاء: `lib/data/models/serial_number_model.dart`
- تعديل: `lib/data/datasources/services/stock_service.dart`
- تعديل: `lib/data/datasources/migrations/schema.dart`
- اختبار: `test/data/services/item_tracking_test.dart`

- [ ] حفظ كمية السطر بوحدة الإدخال وكمية أساسية بعد التحويل.
- [ ] إضافة دفعات مستقلة بتكلفة وتاريخ صلاحية وكمية.
- [ ] إضافة سيريال/IMEI مستقل مرتبط بالصنف وحركة الشراء والبيع والمرتجع والضمان.
- [ ] منع بيع سيريال غير متاح أو إرجاع سيريال مختلف عن سيريال الفاتورة.
- [ ] إضافة FEFO اختياري للأصناف ذات الصلاحية دون فرضه على التجارة العادية.

## المهمة 10: توحيد الفواتير وPOS والمرتجعات

**الملفات:**

- تعديل: `lib/data/datasources/repositories/invoice_repository.dart`
- تعديل: `lib/core/viewmodels/pos_viewmodel.dart`
- تعديل: `lib/ui/screens/invoices/create_invoice_screen.dart`
- تعديل: `lib/ui/screens/pos/pos_screen.dart`
- اختبار: `test/data/repositories/invoice_repository_accounting_test.dart`

- [ ] جعل POS ينشئ نفس نموذج المستند ونفس `TaxEngine` و`PostingEngine` و`InventoryCostEngine`.
- [ ] دعم البيع النقدي والآجل والدفع الجزئي والعربون دون قيود مكررة.
- [ ] جعل المرتجع مرجعًا للفواتير الأصلية والسطور والكميات والتكلفة، مع منع تجاوز الكمية القابلة للإرجاع.
- [ ] إضافة فحص أن مجموع طرق الدفع يساوي المدفوع فعليًا.
- [ ] اختبار بيع خدمة، بيع قطعة، بيع bundle، ومرتجع جزئي.

## المهمة 11: تقارير صاحب المحل والمطابقة

**الملفات:**

- تعديل: `lib/data/datasources/services/report_service.dart`
- تعديل: `lib/ui/screens/reports/widgets/report_data_loader.dart`
- إنشاء: `lib/core/finance/reconciliation_service.dart`
- اختبار: `test/data/services/reconciliation_service_test.dart`

- [ ] إضافة مطابقة دفتر الأستاذ مع حركات المصدر، ومطابقة المخزون الكمي والقيمي، ومطابقة الصندوق مع طرق الدفع.
- [ ] إضافة تقارير: المبيعات، الربح الإجمالي، المخزون، الأصناف الراكدة، الديون، المصروفات، الضرائب، حركة الصندوق، وفروقات الجرد.
- [ ] جعل التقرير يعرض تحذيرًا عند وجود تكلفة معلقة أو قيود معزولة أو مستند غير مرحّل.
- [ ] منع عرض ربحية نهائية إذا كانت هناك أخطاء مطابقة حرجة؛ يعرض النظام حالة “يحتاج تسوية”.

**بوابة P1:** اعتماد نسخة تجارة صغيرة على بيانات اختبار ثابتة، مع نجاح مطابقة المبيعات والمخزون والصندوق والذمم والضريبة.

---

# المرحلة P2: الخدمات والصيانة ومحلات الهواتف

## المهمة 12: نموذج الجهاز وأمر الخدمة

**الملفات:**

- إنشاء: `lib/data/models/service_order_model.dart`
- إنشاء: `lib/data/models/service_device_model.dart`
- إنشاء: `lib/data/datasources/migrations/migration_v57_to_v58.dart`
- إنشاء: `lib/data/datasources/services/service_order_service.dart`
- اختبار: `test/data/services/service_order_service_test.dart`

- [ ] إنشاء الجداول `service_orders`, `service_order_devices`, `service_order_lines`, `service_status_history`, `service_payments`, `service_warranties`.
- [ ] تعريف الحالات: `received`, `diagnosing`, `awaiting_approval`, `in_repair`, `waiting_part`, `ready`, `delivered`, `cancelled`.
- [ ] حفظ الجهاز وIMEI/Serial والحالة والملحقات والعيب المبلغ عنه وموافقة العميل.
- [ ] منع التسليم عند وجود رصيد مستحق أو جعل ذلك إعدادًا صريحًا للصلاحيات.
- [ ] ربط أمر الخدمة بالعميل والفاتورة والدفعات دون تحويله إلى فاتورة قبل إتمام الدورة المطلوبة.

## المهمة 13: ترحيل قطع الغيار وأجور الخدمة والضمان

**الملفات:**

- تعديل: `lib/data/datasources/services/service_order_service.dart`
- تعديل: `lib/data/datasources/repositories/invoice_repository.dart`
- إنشاء: `lib/ui/screens/service_orders/*`
- اختبار: `test/data/services/service_order_posting_test.dart`

- [ ] القطعة المخزنية تنقص من المستودع وتولد COGS عند اعتماد استخدامها.
- [ ] أجور الفني ورسوم الفحص تسجل إيراد خدمة ولا تنقص المخزون.
- [ ] العربون يسجل كالتزام/دفعة مقدمة وفق إعداد المنتج، ولا يعتبر إيرادًا كاملًا قبل الوفاء عند تطبيق سياسة الاعتراف على مدى الخدمة.
- [ ] الضمان المجاني لا ينشئ إيرادًا جديدًا، لكن القطع والتكلفة يجب أن تتبع سياسة الضمان.
- [ ] اختبار إعادة فتح الأمر، إلغاء قطعة، مرتجع قطعة، وضمان بعد التسليم.

**بوابة P2:** اجتياز دورة هاتف كاملة من الاستلام إلى التسليم، مع مطابقة الجهاز والقطعة والأجر والفاتورة والضمان.

---

# المرحلة P3: المخابز والمعاجن والتصنيع الخفيف

## المهمة 14: الوصفات وإصداراتها

**الملفات:**

- إنشاء: `lib/data/models/recipe_model.dart`
- إنشاء: `lib/data/models/recipe_line_model.dart`
- إنشاء: `lib/data/datasources/migrations/migration_v58_to_v59.dart`
- إنشاء: `lib/data/datasources/services/recipe_service.dart`
- اختبار: `test/data/services/recipe_service_test.dart`

- [ ] إنشاء `recipes` و`recipe_lines` مع `version`, `yield_quantity`, `yield_unit`, `effective_from`, `effective_to`.
- [ ] حفظ حساب المكونات بالوحدات الأساسية.
- [ ] منع تعديل وصفة مستخدمة في أمر إنتاج مرحّل؛ إنشاء إصدار جديد.
- [ ] دعم تكلفة المواد والعمالة والتكلفة الإضافية اختياريًا.

## المهمة 15: الإنتاج والاستهلاك والهدر

**الملفات:**

- إنشاء: `lib/data/models/production_order_model.dart`
- إنشاء: `lib/data/datasources/services/production_service.dart`
- إنشاء: `lib/data/datasources/migrations/migration_v59_to_v60.dart`
- إنشاء: `lib/ui/screens/production/*`
- اختبار: `test/data/services/production_service_test.dart`

- [ ] إنشاء أمر إنتاج مرتبط بإصدار وصفة.
- [ ] عند الترحيل، استهلاك المكونات من المستودع وإنشاء الناتج بالتكلفة المحسوبة.
- [ ] تسجيل الإنتاج الفعلي والهدر المنفصل.
- [ ] تسجيل قيد تحويل المواد إلى المنتجات أو إنتاج تحت التشغيل حسب سياسة الإصدار.
- [ ] اختبار إنتاج مخبوزات بكمية فعلية أقل من المخططة، وهدر، وتغيير وصفة لاحق.

**بوابة P3:** لا تتغير تكلفة إنتاج تاريخي عند تعديل الوصفة، وتتطابق كميات المواد والناتج والهدر والحسابات.

---

# المرحلة المشتركة: الأتمتة الآمنة حسب النشاط

## المهمة 16: إعداد النشاط وقواعد الحساب التلقائي

**الملفات:**

- إنشاء: `lib/data/models/business_profile_model.dart`
- إنشاء: `lib/core/business/business_profile_service.dart`
- تعديل: `lib/core/di/service_locator.dart`
- تعديل: `lib/ui/screens/settings/settings_screen.dart`
- اختبار: `test/core/business/business_profile_service_test.dart`

- [ ] تعريف ملفات نشاط أولية: تجارة تجزئة، محل هواتف، صيانة هواتف، مخبز/معجنات، خدمات مهنية، وتجارة جملة.
- [ ] كل ملف نشاط يحدد أنواع العناصر، الحسابات الافتراضية، طريقة التكلفة، الضرائب، الوحدات، السماح بالبيع الآجل، والوحدات المتاحة.
- [ ] عدم إنشاء حسابات أو قيود تلقائية دون عرض معاينة قابلة للفهم للمستخدم.
- [ ] السماح للمحاسب المتقدم بتعديل الربط، مع منع المستخدم العادي من تغيير الحسابات الحساسة دون صلاحية.
- [ ] إضافة معالج إعداد أولي ينشئ الحسابات الافتراضية والفترات والمخزن والصندوق وقواعد الضريبة.

## المهمة 17: الأتمتة والرقابة القابلة للتفسير

**الملفات:**

- إنشاء: `lib/core/finance/automation_explanation.dart`
- تعديل: `lib/ui/screens/audit/accounting_audit_screen.dart`
- تعديل: `lib/data/datasources/services/report_service.dart`
- اختبار: `test/core/finance/automation_explanation_test.dart`

- [ ] لكل عملية آلية، حفظ سبب القيد: “بيع مخزني”، “ضريبة بيع”، “COGS من طبقة FIFO”، “عكس جرد”، “استهلاك وصفة”.
- [ ] عرض معاينة القيد قبل الترحيل في العمليات غير المتكررة أو ذات القيمة الكبيرة.
- [ ] إضافة حدود صلاحيات: خصم أكبر من نسبة معينة، بيع تحت التكلفة، إلغاء مرحّل، تعديل سعر صرف، وجرد بقيمة كبيرة.
- [ ] تسجيل المستخدم والجهاز والتاريخ والسبب في سجل تدقيق غير قابل للحذف العادي.
- [ ] عدم استخدام الذكاء الاصطناعي أو التخمين لاتخاذ قيد محاسبي نهائي؛ الأتمتة تكون من قواعد معلنة قابلة للاختبار.

---

# الاختبارات والاعتماد

## المهمة 18: اختبارات المحركات

**الملفات:**

- `test/core/finance/money_engine_test.dart`
- `test/core/finance/tax_engine_test.dart`
- `test/core/finance/posting_engine_test.dart`
- `test/core/finance/period_guard_test.dart`
- `test/data/services/costing_engine_service_test.dart`

- [ ] اختبار توازن كل قيد في العملة الأصلية والأساسية.
- [ ] اختبار الذرية: فشل أي سطر يؤدي إلى rollback كامل.
- [ ] اختبار عدم تغير المستند التاريخي بعد تغير سعر الصرف أو وصفة أو طريقة تكلفة.
- [ ] اختبار منع العكس المكرر والحذف المباشر.

## المهمة 19: اختبارات سيناريوهات الأعمال

**الملفات:**

- إنشاء: `test/golden/accounting_scenarios/*`
- تعديل: `.github/workflows/android-release.yml`

- [ ] تشغيل سيناريوهات البيع والشراء والمرتجع والجرد والتحويل والصيانة والإنتاج.
- [ ] إضافة فحوصات مطابقة آلية بعد كل سيناريو: دفتر الأستاذ، المخزون، الصندوق، العملاء، الموردون، الضريبة، والربح الإجمالي.
- [ ] تشغيل `flutter analyze` و`flutter test` وبناء debug/release على CI.
- [ ] إيقاف CI إذا فشلت أي قاعدة توازن أو مطابقة مالية، حتى لو نجح بناء الواجهة.

## المهمة 20: اختبار الترحيل والنسخ الاحتياطي

**الملفات:**

- `lib/data/datasources/migrations/*`
- `lib/core/services/portable_backup_service.dart`
- إنشاء: `test/data/migrations/migration_integrity_test.dart`
- إنشاء: `test/core/services/backup_restore_integrity_test.dart`

- [ ] إنشاء نسخة احتياطية قبل كل migration.
- [ ] اختبار قاعدة قديمة تحتوي على فواتير ومخزون وقيود متعددة العملات ثم تشغيل كل migrations بالتسلسل.
- [ ] التحقق من عدد القيود وتوازنها والأرصدة والطبقات بعد الترحيل.
- [ ] اختبار استعادة النسخة على جهاز نظيف وفشل الاستعادة الجزئية.

---

# معايير قبول الإصدار التجاري

لا يعتمد الإصدار التجاري إلا إذا تحققت الشروط التالية:

| المجال | معيار القبول |
|---|---|
| القيود | كل مستند مرحّل يولد قيدًا متوازنًا قابلًا للتتبع، وكل عكس مرتبط بالأصل |
| الحذف | لا يوجد حذف صامت لمستند مالي مرحّل |
| النقود | لا توجد حسابات `double` في نتيجة قيد أو تكلفة أو ضريبة |
| الضرائب | نفس النتيجة تظهر في الشاشة والقيد والتقرير والمرتجع |
| المخزون | كمية وقيمة المخزون تتطابقان مع حركة المستودع وحساب الأستاذ |
| التكلفة | كل COGS يملك طبقة أو سبب تكلفة معلنًا، ولا يوجد fallback صامت |
| الخدمات | الخدمة لا تنقص المخزون، والقطعة تنقصه، وأمر العمل يتتبع الجهاز والضمان |
| الإنتاج | الوصفة التاريخية ثابتة، والاستهلاك والناتج والهدر متطابقة |
| الفترات | الإقفال يمنع التعديل والترحيل غير المصرح به |
| الأمان | سجل التدقيق والنسخة الاحتياطية والاستعادة مجربة |
| Android | ينجح `flutter analyze`, `flutter test`, و`flutter build appbundle` على CI |

## ترتيب التنفيذ المقترح

يُنفذ العمل في فروع مستقلة بترتيب: `p0-finance-core`، ثم `p0-money-tax-costing`، ثم `p1-retail-inventory`، ثم `p2-service-repair`، ثم `p3-production-recipes`، ثم `automation-and-audit`. كل فرع ينتهي باختبارات ومراجعة قبل دمجه. لا تُنفذ وحدتا الصيانة والإنتاج بالتوازي مع إعادة كتابة محرك الترحيل؛ يجب أن تعتمد كلتاهما على الواجهات النهائية للنواة المالية.

## نقاط قرار إلزامية مع صاحب المنتج

قبل تثبيت قواعد الضريبة يجب تحديد الدولة أو الدول المستهدفة ونوع التسجيل الضريبي. وقبل تفعيل التكاليف الصناعية يجب تحديد ما إذا كان الإصدار الأول يريد تكلفة مواد فقط أم تكلفة مواد وعمالة وتكاليف غير مباشرة. أما بقية قواعد الأتمتة المقترحة فهي قواعد سلامة عامة ولا تتطلب قرارًا تجاريًا لتطبيقها.

## المراجع

[1]: https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/ "IFRS Foundation — IAS 2 Inventories"

[2]: https://www.ifrs.org/issued-standards/list-of-standards/ifrs-15-revenue-from-contracts-with-customers/ "IFRS Foundation — IFRS 15 Revenue from Contracts with Customers"
