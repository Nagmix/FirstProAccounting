# تقرير استكمال تدقيق وتطوير FirstProAccounting

**التاريخ:** 27–28 أغسطس 2026
**الفرع:** `main`
**آخر commit موثق:** `b52e3a5 docs: sync report with final HEAD`
**حالة الشجرة:** نظيفة ومتزامنة مع `origin/main`

## النتيجة التنفيذية

أُغلقت في هذه الجولة مجموعة الفجوات المحاسبية الأكثر خطورة في دورة الفواتير والإلغاء: فصل ضريبة القيمة المضافة عن صافي المبيعات والمشتريات في قيود العكس، دعم البيع الجزئي الخاضع للضريبة، تغطية إلغاء مرتجعات البيع والشراء، استعادة مخزون مرتجع المبيعات، منع التحصيل من فاتورة ملغاة، ومنع واجهة الحذف القديمة من حذف مستند مرحّل. بقيت التغييرات مباشرة على `main`، ولم تُعدّل migrations من v2 إلى v58، ولم تُضف أي تبعية جديدة.

> **الحكم الحالي:** التطبيق أصبح أكثر أماناً محاسبياً وقابلاً للتحقق، لكنه **ليس production-ready بلا تحفظ** بعد. ما زال اختبار الاستعادة end-to-end على Android الفعلي غير منجز، كما توجد حدود تشغيلية موثقة أدناه.

## التغييرات المنفذة في هذه الجولة

| المجال | التغيير | دليل RED/GREEN عبر GitHub Actions |
|---|---|---|
| إلغاء البيع النقدي الخاضع للضريبة | عكس صافي الإيراد في `4100` وعكس ضريبة المبيعات في `2300` كلٌّ على حدة، مع إبقاء النقد/العميل بالإجمالي، وإبقاء عكس COGS والمخزون متوازناً. | RED صالح في `d29a5f8`، ثم GREEN في `d835396`؛ نجح run [`33121933613`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33121933613). |
| إلغاء الشراء الخاضع للضريبة | عكس صافي المشتريات في `3100` وضريبة المدخلات في `1400` على حدة بدلاً من تحميل الإجمالي على المشتريات. شمل الإصلاح الكامل والجزئي. | RED في `7b5d13a` وGREEN في `a08c0a2`؛ نجح run [`33122668629`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33122668629). |
| إلغاء البيع الجزئي الضريبي | عكس `100` على المبيعات و`15` على VAT، مقابل `40` نقداً و`75` على العميل، مع توازن القيد واستعادة المخزون. | RED سلوكي بعد تصحيح fixture في `e71502d`، ثم GREEN في `2877da6`؛ run GREEN اللاحق ضمن سلسلة التحقق، ونجح run [`33123320209`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33123320209) بعد اكتمال fixture المناسب. |
| إلغاء مرتجع المبيعات الضريبي | عكس الإشارات الصحيحة لمرتجع البيع: صافي المبيعات وVAT إلى الجانب الدائن في قيد الإلغاء مقابل النقد المدين، بدلاً من عكس الإجمالي في حساب المبيعات. | RED في `ffdbd01` ثم تصحيح توقعات الإشارة في `d3d94c9`، ثم GREEN في `2192f2b` بعد إغلاق فجوة المخزون. |
| إلغاء مرتجع المشتريات الضريبي | عكس صافي المشتريات وVAT receivable في الجانب المدين مقابل النقد/المورد الدائن، مع توازن القيد. | RED في `ffdbd01` وGREEN في `2192f2b`. |
| مخزون مرتجع المبيعات | أُضيف `sale_return` إلى فرع استعادة/تخفيض المخزون عند الإلغاء؛ كان الإلغاء يترك كمية المرتجع في المخزون بدلاً من عكسها. | أثبته فشل RED في `2192f2b` (`Expected 0.0`, `Actual 1.0`) ثم نجح GREEN في [`33126697231`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33126697231). |
| POS deferred مع الضريبة | أُضيف سيناريو post عبر `ShiftService.postShiftInvoices` ثم cancel عبر `InvoiceRepository.cancelInvoice`، مع فحص snapshot، توازن reversal، فصل `4100/2300`، النقد، وعودة المخزون. | بعد تصحيح fixtures الخاصة بالحسابات ووحدات minor وحركة المخزون، نجح الاختبار في run [`33125540660`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33125540660). لم يكن يلزم تعديل إنتاج إضافي في POS لهذه الحالة لأن المسار القائم كان متوافقاً مع توقعات الإلغاء بعد اكتمال fixtures الواقعية. |
| تحصيل بعد الإلغاء | `recordInvoicePayment` يرفض الفاتورة الملغاة أو غير المرحّلة قبل تحديث المبلغ أو إنشاء القيد، ويحافظ على `paid_amount` و`remaining` دون تغيير عند الرفض. | RED في `c4b2599` ثم GREEN في `3502006`؛ نجح run [`33124268074`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33124268074). |
| واجهة الحذف القديمة | `deleteInvoiceWithCascade` أصبحت draft-only؛ ترفض الفاتورة غير المسودة أو التي تحمل `is_posted = 1` قبل حذف البنود أو القيود أو الحركات. | RED في `c4b2599` ثم GREEN في `3502006`. واجهة `deleteInvoice` الحديثة محمية أيضاً من الجولة السابقة. |
| tax snapshots | اختبارات POS تتحقق من بقاء snapshot الأصلي كما هو بعد الإلغاء، بالإضافة إلى اختبارات snapshot المستقلة التي تثبت عدم تغيّره عند تغيير السياسة الحالية. | تحقق snapshot في اختبار POS الضريبي، ونجاح اختبارات `document_tax_snapshot_test.dart` و`invoice_tax_policy_posting_test.dart` ضمن run النهائي. |

## ما تم التحقق منه سابقاً وما بقي سليماً

تظل حماية `BusinessProfile` رافضة للعملة غير الفعالة وقافلة تغيير العملة الأساسية بعد وجود بيانات مالية مرحّلة. كما تظل سياسة `PortableBackupPathPolicy` رافضة لمسارات traversal، و`PortableBackupFileCommitter` قادرة على تبديل قاعدة البيانات والمرفقات مع rollback وsidecars، و`PortableBackupDatabaseValidator` قادرة على فحص إصدار schema المقبول و`PRAGMA integrity_check` وإغلاق اتصال staged حتى عند الخطأ.

| المحور السابق | الحالة | الدليل |
|---|---|---|
| العملة الأساسية غير الفعالة | مغلق | `5687d48` وCI `33034592722` |
| قفل العملة بعد الترحيل | مغلق | `f1aedf4` وCI `33035132671` |
| path traversal في restore | مغلق على مستوى السياسة والمسار | `9d7019d` وCI `33035684538` |
| rollback لتبديل ملفات restore | مغلق على مستوى committer | `f370fc0` وCI `33036757455` |
| staged database validation | مغلق على مستوى validator واختبارات SQLite FFI | `66866d1` وCI `33120343336` |
| حذف الطلبات غير المسودة | مغلق | `0d12e60` وCI `33037320989` |
| حذف الفاتورة المرحّلة عبر API الحديث | مغلق | `88f0696` وCI `33037848019` |

## تحقق GitHub Actions النهائي

آخر تحقق كامل كان للـHEAD `b52e3a5` عبر run [`33128573384`](https://github.com/Nagmix/FirstProAccounting/actions/runs/33128573384). النتيجة `success`، وسجل التشغيل يثبت **966 اختباراً ناجحاً**، مع نجاح التحليل والبناء والتوقيع ورفع artifacts.

| خطوة CI | النتيجة |
|---|---|
| Flutter analyze | success |
| Flutter tests | success — **966 اختباراً ناجحاً** |
| Release APK | success |
| Release AAB | success |
| APK signing | success |
| AAB signing | success |
| رفع APK/AAB | success |
| إزالة الملفات الحساسة | success |

## مراجعة الجودة على المحاور الخمسة

| المحور | نتيجة المراجعة |
|---|---|
| **Correctness** | الإصلاحات الجديدة تعكس VAT على حساب مستقل، وتحافظ على صافي المبيعات/المشتريات، وتختبر الإشارات المختلفة للفاتورة والمرتجع والدفع الجزئي وPOS، مع قيود reversal متوازنة ومخزون قابل للعكس. |
| **Readability** | التغييرات الإنتاجية صغيرة نسبياً ومحصورة في فروع lifecycle القائمة. أسماء الاختبارات تصف السلوك المالي، بينما بقيت حسابات minor عند حدود التخزين والقيد. |
| **Architecture** | تم الحفاظ على transaction boundaries الحالية، وعدم إدخال nested database reads جديدة داخل transaction. يبقى `invoice_repository.dart` كبيراً، وهو دين معماري معروف لا ينبغي توسيعه بلا استخراج تدريجي. |
| **Security** | لا توجد أسرار جديدة أو تبعيات جديدة. حراس الحذف والتحصيل يعملون قبل التأثيرات الجانبية، وrestore يحتفظ بفحص HMAC والتشفير وschema وintegrity ومسارات المرفقات. |
| **Performance** | لا توجد حلقات جديدة غير محدودة أو استعلامات list غير مقيدة في التغييرات. عمليات الإلغاء تستعمل الاستعلامات الموجودة داخل transaction، وrestore عملية نادرة وليست مساراً ساخناً. |

## القيود المتبقية وعدم الادعاء بالجاهزية الكاملة

أولاً، لا يزال التطبيق **local-first** عمداً: لا sync ولا multi-user في هذا الإصدار وفق طلب المستخدم، ولا ينبغي اعتبار غيابهما عيباً في هذه الجولة. الملكية الحالية هي جهاز/قاعدة محلية لمستخدم واحد.

ثانياً، اختبار restore end-to-end الكامل لخدمة `PortableBackupService` لم يُنجز على Android فعلي. الاختبارات الحالية حقيقية ومفيدة للـvalidator والـpath policy والـcommitter، لكنها لا تثبت دورة كاملة تشمل `FlutterSecureStorage` و`path_provider` وSQLCipher ومفتاح الجهاز وتبديل الملفات على Android. كما أن `PortableBackupCompatibility` تقبل الإصدارات المتوافقة فقط ولا تنفذ ترقية restore تلقائية لقاعدة قديمة.

ثالثاً، تم اختبار snapshot في مسار POS وفي الاختبارات المستقلة، لكن يجب إبقاء اختبار Android instrumentation أو جهاز فعلي ضمن بوابة الإطلاق النهائية للتأكد من تفاعل secure storage ودورة حياة التطبيق أثناء restore والانقطاع.

رابعاً، ما زالت `invoice_repository.dart` كبيرة وتضم فروع lifecycle متعددة. الحل طويل المدى هو استخراج dispatcher أو خدمات منفصلة للـposting وreversal وsettlement، لكن ذلك refactor مستقل يجب تنفيذه لاحقاً مع TDD ولا ينبغي خلطه مع إصلاحات هذه الجولة.

خامساً، ما زالت التحذيرات القديمة غير الحاجزة موجودة في `flutter analyze`؛ التحليل نجح، لكن تنظيف التحذيرات ورفع quality gate إلى `--fatal-infos` قرار إصدار مستقل.

سادساً، لا يوجد تشغيل Flutter/Dart محلي في هذه البيئة. كل نتائج التحليل والاختبارات والبناء والتوقيع الواردة هنا مبنية على GitHub Actions فقط.

## قائمة تحقق الإصدار الأول

| البند | الحالة الحالية |
|---|---|
| أموال التخزين في INTEGER minor | مطبق ومغطى باختبارات MoneyHelper وقيود الدفع |
| قيود مالية متوازنة وقابلة للتدقيق | مطبق في السيناريوهات المغطاة، مع reversal غير مدمر |
| عدم حذف مستند/قيد مرحّل | محمي في APIs الحديثة والقديمة التي تم تدقيقها |
| tax snapshots مؤرخة وغير قابلة للتعديل | مطبق ومختبر في direct posting وPOS وrepository |
| purchase/sale/return/POS cancellation | مغطى بالسيناريوهات الضريبية والجزئية المناسبة |
| rollback واستعادة الملفات | مغطى على مستوى الوحدات الحقيقية، لا Android end-to-end بعد |
| RTL والبساطة والقدرات | موجودة من الشرائح السابقة، وتحتاج اختبار قبول UI على جهاز فعلي قبل الإطلاق |
| sync وmulti-user | **مستثنيان صراحة من هذا الإصدار** |

## الملفات الأساسية الجديدة أو المعدلة

| الملف | الغرض |
|---|---|
| `lib/data/datasources/repositories/invoice_repository.dart` | عكس VAT للمبيعات والمشتريات والمرتجعات، دعم الإلغاء الجزئي، حراس الدفع والحذف، واستعادة مخزون sale return |
| `lib/data/datasources/services/shift_service.dart` | مسار ترحيل POS المؤجل الذي تمت مراجعته واختباره بالـsnapshot والـcancellation parity |
| `test/acceptance/accounting_business_scenarios_acceptance_test.dart` | سيناريوهات البيع والشراء والمرتجعات والإلغاء الضريبي والجزئي والمخزون |
| `test/integration/pos_tax_policy_posting_test.dart` | post/cancel POS الضريبي، snapshot immutable، reversal، cash، stock |
| `test/unit/invoice_repository_lifecycle_test.dart` | حراس الدفع بعد الإلغاء وحذف cascade القديم |
| `lib/core/services/portable_backup_path_policy.dart` | سياسة أمان مسارات المرفقات |
| `lib/core/services/portable_backup_file_committer.dart` | تبديل ملفات restore وrollback |
| `lib/core/services/portable_backup_database_validator.dart` | فحص staged schema وintegrity |

## مراجع CI والمشروع

- [GitHub Actions run 33128573384 — final HEAD](https://github.com/Nagmix/FirstProAccounting/actions/runs/33128573384)
- [GitHub Actions run 33125540660 — POS deferred posting/cancellation verification](https://github.com/Nagmix/FirstProAccounting/actions/runs/33125540660)
- [GitHub Actions run 33124268074 — payment and legacy delete guards](https://github.com/Nagmix/FirstProAccounting/actions/runs/33124268074)
- [GitHub Actions run 33122668629 — purchase VAT cancellation](https://github.com/Nagmix/FirstProAccounting/actions/runs/33122668629)
- [GitHub Actions run 33121933613 — sale VAT cancellation](https://github.com/Nagmix/FirstProAccounting/actions/runs/33121933613)
- [GitHub repository Nagmix/FirstProAccounting](https://github.com/Nagmix/FirstProAccounting)
