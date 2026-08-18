# خطة تنفيذ وحدة الخدمات والصيانة

> **للعاملين الوكيليين:** يجب تنفيذ هذه الخطة مهمةً بعد مهمة، مع اختبار كل مهمة قبل الانتقال إلى التالية. استخدم أسلوب TDD: اكتب الاختبار، شغّله ليثبت الفشل الصحيح، اكتب أقل كود يحقق النجاح، ثم شغّل الاختبار وجميع الاختبارات ذات الصلة.

**الهدف:** إضافة وحدة خدمات وصيانة محاسبية آمنة تدير أوامر الخدمة والأجهزة والبنود والحالات والدفعات والضمانات، مع فصل الخدمات عن المخزون وربط قطع الغيار بترحيل المخزون وCOGS الموجود.

**المعمارية:** ستضاف طبقة بيانات مستقلة لجداول v57، ونماذج immutable، وخدمة `ServiceOrderService` تستخدم معاملات SQLite وخدمات القيود والمخزون الحالية. لا تعدل الوحدة الجداول أو الترحيلات التاريخية، ولا تكتب مباشرة في أرصدة العملاء أو الصناديق أو المخزون خارج الخدمات الموجودة.

**التقنيات:** Flutter/Dart 3.3، SQLite/SQLCipher عبر `sqflite_sqlcipher`، Provider/GetIt، `MoneyHelper`، `CurrencyEngine`، `InvoiceTotalsEngine`، `JournalValidator`، `StockService`، وGitHub Actions للتحليل والاختبارات وبناء Android.

**المواصفة:** `docs/superpowers/specs/2026-08-18-service-maintenance-design.md`

## القيود العامة

- العمل مباشرة على الفرع `main`، دون إنشاء worktree.
- لا يتوفر Flutter محلياً؛ التحقق النهائي يكون عبر GitHub Actions.
- لا تثبت حزم Flutter محلياً للفحص فقط.
- لا تعدل الترحيلات v2 إلى v56؛ أضف `migration_v57.dart` فقط.
- لا تحذف ميزة قائمة ولا تكسر نمط طبقات المشروع.
- كل مبلغ جديد يخزن بوحدات صغرى صحيحة عند حد قاعدة البيانات.
- كل `amount_base` يحسب عبر `CurrencyEngine` لا بضرب عائم مباشر.
- الخدمة لا تنشئ حركة مخزون أو COGS للخدمات و`nonStock`.
- الصنف `stock` أو `bundle` فقط يمكن أن يشارك في حركة قطع الغيار مع احترام `track_stock`.
- لا تعديل أو حذف لأمر مرحّل؛ الإلغاء يستخدم عكساً قابلاً للتدقيق.
- كل قيد يمر عبر `JournalValidator` ويُحفظ داخل معاملة ذرية.
- بعد كل مجموعة منطقية يجب إنشاء commit ثم دفعه ومراقبة CI قبل الانتقال المحاسبي التالي.

---

### المهمة 1: اختبارات العقد وقواعد بنود الخدمة

**الملفات:**
- إنشاء: `test/core/service/service_order_model_test.dart`
- إنشاء: `test/core/service/service_order_policy_test.dart`
- قراءة مرجعية: `lib/data/models/product_model.dart`, `lib/core/finance/invoice_totals_engine.dart`

**الواجهات الناتجة:**
- `ServiceOrderLineType.service` و`ServiceOrderLineType.part`.
- دالة سياسة صريحة قابلة للاختبار، مثل `ServiceOrderLinePolicy.canAffectInventory({required String lineType, required ProductKind productKind, required bool trackStock})`، تعيد `false` للخدمة و`nonStock`، وتعيد `true` فقط للقطعة ذات `stock` أو `bundle` و`trackStock = true`.
- نماذج `ServiceOrder`, `ServiceOrderLine`, و`ServiceOrderDevice` ستوفر لاحقاً `fromMap`, `toMap`, و`copyWith`.

- [ ] **الخطوة 1: اكتب اختباراً فاشلاً لسياسة المخزون.**

```dart
test('service line never affects inventory', () {
  expect(
    ServiceOrderLinePolicy.canAffectInventory(
      lineType: 'service',
      productKind: ProductKind.stock,
      trackStock: true,
    ),
    isFalse,
  );
});

test('non-stock product cannot affect inventory as a part', () {
  expect(
    ServiceOrderLinePolicy.canAffectInventory(
      lineType: 'part',
      productKind: ProductKind.nonStock,
      trackStock: true,
    ),
    isFalse,
  );
});

test('tracked stock and bundle parts affect inventory', () {
  for (final kind in [ProductKind.stock, ProductKind.bundle]) {
    expect(
      ServiceOrderLinePolicy.canAffectInventory(
        lineType: 'part',
        productKind: kind,
        trackStock: true,
      ),
      isTrue,
    );
  }
});
```

- [ ] **الخطوة 2: شغّل الاختبار على GitHub Actions أو بيئة Dart المتاحة للتحقق من فشل تعريف الواجهة، ولا تكتب كود الإنتاج بعد.**
- [ ] **الخطوة 3: اكتب أقل تنفيذ للسياسة في ملف إنتاج مستقل `lib/core/service/service_order_line_policy.dart`.**
- [ ] **الخطوة 4: أعد تشغيل الاختبار، ثم أضف حالات رفض `lineType` غير المعروفة و`track_stock = false`.**
- [ ] **الخطوة 5: نفّذ اختباراً فاشلاً لعقد `ServiceOrderLine` في الوحدات الصغرى، ثم أضف النموذج والخريطة ذهاباً وإياباً دون تحويل مزدوج.**
- [ ] **الخطوة 6: شغّل اختبارات هذه المهمة عبر CI، ثم أنشئ commit:**

```bash
git add lib/core/service test/core/service
git commit -m "test: define service order line accounting policy"
git push origin main
```

---

### المهمة 2: نماذج أوامر الخدمة والأجهزة والدفعات

**الملفات:**
- إنشاء: `lib/data/models/service_order_model.dart`
- إنشاء: `lib/data/models/service_order_line_model.dart`
- إنشاء: `lib/data/models/service_order_device_model.dart`
- إنشاء: `lib/data/models/service_payment_model.dart`
- إنشاء: `lib/data/models/service_warranty_model.dart`
- تعديل: `test/core/service/service_order_model_test.dart`

**الواجهات:**

```dart
class ServiceOrder {
  final String id;
  final String orderNumber;
  final int? customerId;
  final String status;
  final String priority;
  final DateTime receivedAt;
  final DateTime? promisedAt;
  final String currencyCode;
  final double exchangeRate;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double transportCharges;
  final double total;
  final double paidAmount;
  final double remaining;
  final bool isPosted;
  final int? postedJournalId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ServiceOrderLine {
  final int? id;
  final String serviceOrderId;
  final String lineType;
  final int? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double unitCost;
  final double taxRate;
  final double taxAmount;
  final double lineTotal;
  final String currencyCode;
  final bool isPosted;
}
```

- [ ] **الخطوة 1: وسّع الاختبارات لتتحقق من default status `draft`, العملة `YER`, سعر الصرف `1.0`, وتحويل أعمدة المبالغ بالوحدات الصغرى في `toMap`.**
- [ ] **الخطوة 2: شغّل اختبارات النماذج لتثبت الفشل بسبب الملفات غير الموجودة.**
- [ ] **الخطوة 3: نفّذ النماذج باستخدام أسلوب النماذج الحالية، واجعل `toMap` يعيد القيم عند حدود النموذج كما يتوقع المشروع، مع استخدام `MoneyHelper.toCentsMap` قبل الإدراج في SQLite فقط.**
- [ ] **الخطوة 4: أضف اختبارات رفض العملة الفارغة وسعر الصرف غير الموجب والكميات غير الموجبة في validator مستقل.**
- [ ] **الخطوة 5: شغّل اختبارات النماذج كاملة، ثم commit ودفع:**

```bash
git add lib/data/models/service_* test/core/service
 git commit -m "feat: add service order data models"
git push origin main
```

---

### المهمة 3: ترحيل v57 والجداول والفهارس

**الملفات:**
- إنشاء: `lib/data/datasources/migrations/migration_v57.dart`
- تعديل: `lib/data/datasources/migrations/migration_runner.dart`
- تعديل: `lib/data/datasources/database_helper.dart`
- تعديل: `lib/core/constants/app_constants.dart`
- تعديل: `lib/data/datasources/migrations/schema.dart` لإضافة جداول التثبيت الجديد فقط
- إنشاء: `test/regression/service_order_migration_regression_test.dart`

**الواجهات:**

```dart
class MigrationV57 {
  static Future<void> migrate(Database db) async { ... }
}
```

يجب أن تنشئ `migrate` الجداول التالية عبر `CREATE TABLE IF NOT EXISTS`: `service_orders`, `service_order_devices`, `service_order_lines`, `service_status_history`, `service_payments`, `service_warranties`، مع المفاتيح والفهارس المحددة في المواصفة.

- [ ] **الخطوة 1: اكتب guard فاشلاً يثبت وجود استيراد MigrationV57، شرط `oldVersion < 57`, وقيمة `_databaseVersion = 57` و`AppConstants.dbVersion = 57`.**
- [ ] **الخطوة 2: شغّل guard ليثبت فشله بسبب الإصدار 56 وعدم وجود الترحيل.**
- [ ] **الخطوة 3: اكتب MigrationV57 باستخدام معاملات SQLite، وأنشئ قيود `CHECK` البسيطة التي يدعمها SQLite دون الاعتماد على trigger معقد.**
- [ ] **الخطوة 4: اربط الترحيل في `MigrationRunner` بعد v56، وارفع إصداري قاعدة البيانات في `DatabaseHelper` و`AppConstants` إلى 57.**
- [ ] **الخطوة 5: حدّث `DatabaseSchema.onCreate` للجداول الجديدة حتى تبدأ القاعدة الجديدة من آخر مخطط دون انتظار ترقية.**
- [ ] **الخطوة 6: أضف اختبارات مصدرية للجداول والأعمدة الأساسية، واختبار عدم تعديل ملفات v2-v56.**
- [ ] **الخطوة 7: شغّل regression suite عبر CI، ثم commit ودفع:**

```bash
git add lib/data/datasources/migrations/migration_v57.dart lib/data/datasources/migrations/migration_runner.dart lib/data/datasources/database_helper.dart lib/core/constants/app_constants.dart lib/data/datasources/migrations/schema.dart test/regression/service_order_migration_regression_test.dart
git commit -m "feat: add service maintenance database migration v57"
git push origin main
```

---

### المهمة 4: سياسة الحالات وإعادة حساب الإجماليات

**الملفات:**
- إنشاء: `lib/core/service/service_order_status_policy.dart`
- إنشاء: `lib/core/service/service_order_totals.dart`
- تعديل: `test/core/service/service_order_policy_test.dart`
- إنشاء: `test/core/service/service_order_totals_test.dart`

**الواجهات:**

```dart
class ServiceOrderStatusPolicy {
  static bool canTransition(String from, String to);
}

class ServiceOrderTotals {
  static ServiceOrderTotalsResult calculate({
    required List<ServiceOrderLine> lines,
    required double discountAmount,
    required double transportCharges,
  });
}
```

- [ ] **الخطوة 1: اكتب اختبارات فاشلة للانتقالات الصحيحة، رفض الانتقال من `delivered`، ورفض ترحيل `cancelled`.**
- [ ] **الخطوة 2: اكتب اختباراً فاشلاً يثبت أن الإجمالي يعاد من البنود، وأن قيمة رأس الأمر المرسلة من الواجهة لا تؤثر على الناتج.**
- [ ] **الخطوة 3: نفّذ السياسة والحساب باستخدام `InvoiceTotalsEngine` أو محرك إجماليات مشترك، مع تطبيق الضريبة والخصم بالوحدات الصغرى.**
- [ ] **الخطوة 4: أضف حالات الحد الصفري، الخصم الأكبر من المجموع، والكمية الكسرية المسموحة.**
- [ ] **الخطوة 5: شغّل اختبارات النواة الحالية واختبارات الخدمة، ثم commit ودفع:**

```bash
git add lib/core/service test/core/service
 git commit -m "feat: add service order status and totals policies"
git push origin main
```

---

### المهمة 5: خدمة المسودات والبنود وسجل الحالات

**الملفات:**
- إنشاء: `lib/data/datasources/services/service_order_service.dart`
- إنشاء: `test/unit/services/service_order_service_test.dart`
- تعديل: `lib/core/di/service_locator.dart` عند الحاجة لتسجيل الخدمة

**الواجهات:**

```dart
class ServiceOrderService {
  Future<String> createDraft({required ServiceOrder order});
  Future<void> addLine({required String orderId, required ServiceOrderLine line});
  Future<void> updateLine({required ServiceOrderLine line});
  Future<void> removeLine({required String orderId, required int lineId});
  Future<void> transitionStatus({required String orderId, required String toStatus, String? note});
  Future<ServiceOrder?> getById(String orderId);
  Future<List<Map<String, dynamic>>> getStatusHistory(String orderId);
}
```

- [ ] **الخطوة 1: اكتب اختبارات فاشلة لإنشاء مسودة، إضافة بند، إعادة حساب الإجماليات، وتسجيل تغيير الحالة.**
- [ ] **الخطوة 2: اكتب اختبار فشل لمحاولة إضافة `stock` كسطر خدمة، و`service` كسطر قطعة، وعملة لا تطابق عملة الأمر.**
- [ ] **الخطوة 3: نفّذ عمليات المسودة داخل معاملات SQLite، واستخدم استعلامات parameterized فقط.**
- [ ] **الخطوة 4: نفّذ التحقق من ProductKind عبر `ServiceOrderLinePolicy` قبل الإدراج، واحسب الإجماليات من البنود بعد كل تغيير.**
- [ ] **الخطوة 5: نفّذ انتقال الحالة وسجل `service_status_history` في نفس المعاملة.**
- [ ] **الخطوة 6: شغّل اختبارات الخدمة، ثم commit ودفع:**

```bash
git add lib/data/datasources/services/service_order_service.dart lib/core/di/service_locator.dart test/unit/services/service_order_service_test.dart
 git commit -m "feat: add service order draft workflow"
git push origin main
```

---

### المهمة 6: ترحيل أمر الخدمة وقطع الغيار محاسبياً

**الملفات:**
- تعديل: `lib/data/datasources/services/service_order_service.dart`
- تعديل: `lib/core/finance/journal_validator.dart` عند الحاجة فقط إذا ظهرت واجهة عامة لازمة، دون تغيير قواعده الحالية بلا اختبار
- إنشاء: `test/integration/service/service_order_posting_test.dart`
- إنشاء: `test/regression/service_order_accounting_regression_test.dart`

**الواجهات:**

```dart
Future<void> postServiceOrder({required String orderId});
Future<void> cancelServiceOrder({required String orderId, required String reason});
```

- [ ] **الخطوة 1: اكتب اختباراً فاشلاً يثبت أن ترحيل أمر خدمة يحتوي خدمة فقط لا ينشئ `stock_movements` أو COGS.**
- [ ] **الخطوة 2: اكتب اختباراً فاشلاً يثبت أن أمر خدمة يحتوي قطعة `stock` يمر عبر StockService ويثبت تكلفة COGS المناسبة.**
- [ ] **الخطوة 3: اكتب اختباراً فاشلاً يثبت رفض القطعة `service` أو `nonStock`، ورفض الترحيل المكرر، ورفض الترحيل من حالة غير جاهزة.**
- [ ] **الخطوة 4: نفّذ الترحيل داخل transaction واحدة: أعد تحميل الرأس والبنود من SQLite، أعد حساب الإجماليات، تحقق من ProductKind، استدعِ مسار المخزون القائم للقطع، أنشئ القيود، ثم حدث `is_posted` و`posted_journal_id`.**
- [ ] **الخطوة 5: استخدم `reference_type = service_order` و`reference_id = orderId`، وشغّل `JournalValidator` قبل إتمام المعاملة.**
- [ ] **الخطوة 6: نفّذ العكس عند الإلغاء بدلاً من حذف الأمر أو حركاته، وسجل السبب في سجل الحالات.**
- [ ] **الخطوة 7: شغّل اختبارات التكامل والانحدار على CI، ثم commit ودفع:**

```bash
git add lib/data/datasources/services/service_order_service.dart test/integration/service test/regression/service_order_accounting_regression_test.dart
git commit -m "feat: post service orders with inventory-safe accounting"
git push origin main
```

---

### المهمة 7: الدفعات والضمان والتدقيق

**الملفات:**
- تعديل: `lib/data/datasources/services/service_order_service.dart`
- إنشاء: `test/integration/service/service_payment_test.dart`
- إنشاء: `test/core/service/service_warranty_test.dart`

**الواجهات:**

```dart
Future<int> recordPayment({required ServicePayment payment});
Future<void> postPayment({required int paymentId});
Future<int> addWarranty({required ServiceWarranty warranty});
```

- [ ] **الخطوة 1: اكتب اختباراً فاشلاً لرفض الدفعة الصفرية والسالبة والدفعة الأكبر من المتبقي.**
- [ ] **الخطوة 2: اكتب اختباراً فاشلاً يثبت أن `amount_base` يساوي ناتج `CurrencyEngine` وأن الترحيل المكرر مرفوض.**
- [ ] **الخطوة 3: نفّذ تسجيل الدفعة داخل transaction، مع تحديث `paid_amount` و`remaining` بعد إعادة حساب رأس الأمر.**
- [ ] **الخطوة 4: نفّذ ترحيل الدفعة عبر خدمة القيود والصندوق القائمة، مع reference `service_payment`، دون تعديل الرصيد مباشرة.**
- [ ] **الخطوة 5: أضف عمليات الضمان والتحقق من أن تاريخ النهاية لا يسبق تاريخ البداية، دون إنشاء قيد مالي.**
- [ ] **الخطوة 6: شغّل اختبارات الدفعات والضمان وكل اختبارات النواة، ثم commit ودفع:**

```bash
git add lib/data/datasources/services/service_order_service.dart test/integration/service test/core/service
 git commit -m "feat: add service payments and warranties"
git push origin main
```

---

### المهمة 8: اختبارات القبول والتوثيق النهائي

**الملفات:**
- إنشاء: `test/acceptance/service_maintenance_acceptance_test.dart`
- تعديل: `test/regression/deep_accounting_audit_regression_test.dart` عند إضافة guards لازمة
- تعديل: `AGENTS.md` لتسجيل v57 ونمط وحدة الخدمة
- إنشاء: `docs/service-maintenance-acceptance-ar.md`

- [ ] **الخطوة 1: اكتب سيناريو قبول خدمة فقط: إنشاء، تغيير حالة، ترحيل، تحقق من عدم وجود حركة مخزون أو COGS، وتوازن القيد.**
- [ ] **الخطوة 2: اكتب سيناريو قبول قطعة غيار: ربط صنف `stock`، ترحيل، تحقق من حركة المخزون وCOGS وتوازن القيد.**
- [ ] **الخطوة 3: اكتب سيناريو رفض `service` و`nonStock` كسطر قطعة، وسيناريو حزمة `bundle` مع `track_stock`.**
- [ ] **الخطوة 4: اكتب سيناريو إلغاء بعد الترحيل، وتحقق من وجود العكس وعدم حذف السجل الأصلي.**
- [ ] **الخطوة 5: اكتب سيناريو عملة أجنبية، وتحقق من الوحدات الصغرى و`amount_base` وعدم وجود تحويل عائم.**
- [ ] **الخطوة 6: شغّل `git diff --check` وفحوصات مصدرية محلية لا تعتمد على Flutter، ثم ادفع آخر commit.**
- [ ] **الخطوة 7: راقب Android Release حتى `completed/success`، واستخرج سجل الفشل إن وجد، وأصلح السبب باختبار انحدار قبل إعادة الدفع.**
- [ ] **الخطوة 8: بعد نجاح CI، حدّث تقرير الحالة النهائي مع أرقام commits وتشغيل CI ونتائج الاختبارات.**

## بوابات الانتقال

لا تبدأ المهمة 3 قبل نجاح اختبارات المهمة 1 و2. لا تبدأ المهمة 6 قبل نجاح ترحيل v57 على CI. لا تبدأ المهمة 7 قبل إثبات أن الترحيل لا ينتج حركة مخزون للخدمات وأن حركة القطع تمر عبر السياسة المركزية. لا تعتبر الوحدة مكتملة قبل نجاح Android build و`flutter analyze` و`flutter test` على GitHub Actions.

## أوامر التحقق

```bash
git diff --check
git status --short
gh run list --repo Nagmix/FirstProAccounting --limit 5
gh run view <RUN_ID> --repo Nagmix/FirstProAccounting --json status,conclusion
```

التحقق النهائي يجب أن يعتمد على GitHub Actions لأن Flutter غير متوفر في البيئة المحلية.
