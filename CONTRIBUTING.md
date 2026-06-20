# دليل المساهمة — FirstPro Accounting

> مرجع تقني للمطورين الذين يعملون على مشروع الأول برو المحاسبي.

## 📂 بنية المشروع

```
lib/
├── main.dart                          # نقطة الدخول + MaterialApp + ThemeProvider
├── core/
│   ├── constants/app_constants.dart   # ثوابت التطبيق (أسماء routes، أنواع، إصدار DB)
│   ├── di/service_locator.dart        # حقن التبعيات (get_it)
│   ├── theme/                         # الثيم + ThemeProvider + DesignSystem
│   ├── utils/                         # أدوات مساعدة (MoneyHelper, formatters, etc.)
│   ├── helpers/                       # مساعدات UI (CurrencyConstants, AvatarHelper, DeleteHelper)
│   ├── extensions/                    # extensions على BuildContext
│   ├── services/                      # خدمات الطباعة + PDF
│   ├── license/                       # نظام الترخيص
│   ├── security/                      # تشفير DB (SQLCipher)
│   └── viewmodels/                    # ViewModels (Dashboard, POS, Invoice)
├── data/
│   ├── models/                        # نماذج البيانات (Account, Product, Invoice, etc.)
│   └── datasources/
│       ├── database_helper.dart       # فتح DB مشفّر + إدارة singleton
│       ├── migrations/                # ترحيلات قاعدة البيانات (v2→v54)
│       ├── repositories/              # مستودعات CRUD (Account, Customer, Invoice, etc.)
│       └── services/                  # خدمات منطق الأعمال (Journal, Costing, Report, etc.)
└── ui/
    ├── navigation/                    # Router + MainScaffold (bottom nav + drawer)
    ├── screens/                       # شاشات التطبيق (50+ شاشة)
    └── widgets/                       # widgetsReusable (StatCard, EmptyState, etc.)
```

## 🔑 المفاهيم الأساسية

### المبالغ المالية (MoneyHelper)

جميع المبالغ المالية تُخزَّن في DB كـ `INTEGER` (سنتات × 100). التحويل إلزامي:

```dart
// كتابة لـ DB:
final dbMap = MoneyHelper.toCentsMap(model.toMap(), MoneyHelper.invoiceMoneyFields);
await db.insert('invoices', dbMap);

// قراءة من DB (عمود مباشر):
final amount = MoneyHelper.readMoney(row['total']); // int → double

// قراءة من DB (نتيجة SQL SUM/CAST):
final total = MoneyHelper.readCalculatedMoney(row['total']); // int/REAL → double (÷100)
```

**الفرق الحاسم**: `readMoney` يكتشف int vs double تلقائياً. `readCalculatedMoney` يقسم دائماً على 100 (لأن SQL SUM قد يُرجع REAL).

### القيد المزدوج (JournalService)

كل عملية مالية تُرحّل عبر `JournalService`:
- `updateAccountBalanceWithJournal(txn, accountId, debit, credit, now)` — تحديث ذري بـ SQL CASE.
- `validateJournalBalanceInTransaction(txn, journalId)` — التحقق من توازن القيد.
- `getOrCreateExchangeAccount(isGain)` — حساب 4700 (مكاسب صرف) / 5300 (خسائر صرف) بـ YER.

### تعدد العملات

- كل عملة لها `code_offset` (YER=0, SAR=1, USD=2, ...).
- `account_code = base_code + offset` (مثلاً: 1100=صناديق YER، 1101=صناديق SAR).
- `BaseCurrencyService.getOffsetForCurrency(code)` يُرجع الـ offset ديناميكياً.
- `amount_base` في جدول `transactions` يخزّن المكافئ بعملة الأساس (YER).

### نظام التكلفة (CostingEngineService)

- **متوسط مرجح**: `products.average_cost` يُحدَّث عند الشراء.
- **FIFO/LIFO**: `inventory_cost_layers` (طبقات تكلفة) تُستهلك عند البيع.
- `reverseCOGSAllocations(invoiceId)` يُعيد الطبقات عند المرتجع.

### الترحيلات (Migrations)

- إصدار DB الحالي: **54** (في `DatabaseHelper._databaseVersion` و `AppConstants.dbVersion`).
- كل ترحيل في ملف منفصل: `migration_vNN.dart`.
- `migration_runner.dart` ينفّذها بالترتيب.
- `schema.dart::onCreate` ينشئ كل الجداول للتركيبات الجديدة.
- **قاعدة**: أي تغيير schema يحتاج migration جديد + تحديث schema.dart + رفع `_databaseVersion`.

### حقن التبعيات (GetIt)

- المستودعات والخدمات: `registerLazySingleton` (مثيل واحد).
- ViewModels: `registerFactory` (مثيل جديد لكل شاشة).
- `DatabaseHelper.markLocatorReady()` يُستدعى بعد التسجيل.

## 🧪 الاختبارات

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings   # 0 أخطاء
flutter test                                           # 730+ اختبار
bash scripts/local_check.sh                            # فحص شامل قبل الدفع
```

### أنواع الاختبارات

| النوع | المسار | الوصف |
|---|---|---|
| Unit | `test/unit/` | اختبارات الوحدات (models, helpers, services) |
| Widget | `test/widget/` | اختبارات widgetsReusable |
| Database | `test/database/` | اختبارات الترحيلات + التكامل مع DB |
| Regression | `test/regression/` | حرّاس ضد عودة أخطاء حرجة |
| Accounting | `test/accounting/` | اختبارات المنطق المحاسبي |
| Integration | `test/integration/` | اختبارات تكامل شاملة |

## 🚀 GitHub Actions

- workflow: `.github/workflows/android-release.yml`
- يعمل عند كل دفع لـ `main`: analyze → test → build APK + AAB موقّعين.
- التوقيع من GitHub Secrets (لا مفاتيح في المستودع).

## 📝 قواعد الكود

1. **المبالغ**: دائماً عبر `MoneyHelper`، لا تستخدم `double` مباشرة في DB.
2. **القيد المزدوج**: كل عملية مالية تُرحّل عبر `JournalService`.
3. **المرتجعات**: موقّعة سالبة في `tax_amount` و `amount_base`.
4. **RTL**: التطبيق عربي أولاً، استخدم `Directionality(textDirection: TextDirection.rtl)`.
5. **الترحيلات**: لا تعدّل جداول موجودة بدون migration آمن.
6. **الاختبارات**: أضف اختبار حارس لكل إصلاح خطأ حرج.
