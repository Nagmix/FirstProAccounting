# تقرير بحثي شامل: نظام POS والورديات والمحاسبة
## Comprehensive Research Report: POS, Shift System & Accounting

---

## 1. نظام نقطة البيع (POS System) - المتطلبات والميزات الأساسية

### 1.1 الميزات الأساسية لنظام POS كامل (Essential Features)

| # | الميزة (Feature) | الوصف |
|---|---|---|
| 1 | **Sales Processing** | معالجة المبيعات (نقداً/آجل/بطاقة) مع دعم Barcode |
| 2 | **Inventory Management** | إدارة المخزون التلقائية (Perpetual Inventory) مع تتبع الكميات |
| 3 | **Payment Processing** | معالجة المدفوعات المتعددة (Cash, Card, Mobile Wallet) |
| 4 | **Customer Management (CRM)** | إدارة العملاء وسجل المشتريات والأرصدة |
| 5 | **Shift Management** | نظام الورديات (Opening/Closing Shift) |
| 6 | **Reporting & Analytics** | التقارير (X-Report, Z-Report, Sales Reports) |
| 7 | **User/Permission Management** | إدارة المستخدمين والصلاحيات (Role-Based Access) |
| 8 | **Tax/VAT Management** | إدارة الضرائب (VAT) التلقائية |
| 9 | **Discounts & Promotions** | نظام الخصومات والعروض الترويجية |
| 10 | **Returns & Refunds** | معالجة المرتجعات والاسترداد |
| 11 | **Multi-Branch Support** | دعم الفروع المتعددة |
| 12 | **Accounting Integration** | التكامل مع نظام القيد المزدوج (Double-Entry Accounting) |

### 1.2 كيف يتكامل POS مع القيد المزدوج (Double-Entry Integration)

نظام POS لا يعمل بمعزل عن المحاسبة - كل عملية بيع تُنشئ تلقائياً Journal Entries في نظام القيد المزدوج:

```
POS Sale Event → Journal Entry (Auto-Generated)
├── Revenue Entry (إيراد)
├── Inventory Entry (مخزون)  
├── Tax Entry (ضريبة)
└── Payment Entry (دفعة)
```

**القاعدة الأساسية:** كل Transaction في POS = Journal Entry واحد أو أكثر في المحاسبة، حيث:
- **Debit (مدين)** = ما يدخل / ما يُستحق للشركة
- **Credit (دائن)** = ما يخرج / ما تدين به الشركة

---

## 2. القيود المحاسبية في نظام POS (POS Accounting Entries)

### 2.1 بيع نقدي (Cash Sale) - مع ضريبة VAT

**مثال:** بيع بضاعة بقيمة 1,000 ريال، ضريبة VAT 15% = 150، تكلفة البضاعة 600

#### القيد الأول: إثبات الإيراد والتحصيل (Revenue Entry)
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| الصندوق/النقدية (Cash) | 1,150 | |
| إيراد المبيعات (Sales Revenue) | | 1,000 |
| ضريبة القيمة المضافة المستحقة (VAT Payable) | | 150 |

#### القيد الثاني: إثبات تكلفة البضاعة المباعة (COGS Entry) - Perpetual Inventory
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| تكلفة البضاعة المباعة (Cost of Goods Sold) | 600 | |
| المخزون (Inventory) | | 600 |

---

### 2.2 بيع آجل (Credit Sale)

**مثال:** بيع بضاعة بـ 1,000 ريال + VAT 150 على الحساب

#### القيد الأول: إثبات الإيراد
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| العملاء/المدينون (Accounts Receivable) | 1,150 | |
| إيراد المبيعات (Sales Revenue) | | 1,000 |
| ضريبة القيمة المضافة المستحقة (VAT Payable) | | 150 |

#### القيد الثاني: COGS (نفس القيد)
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| تكلفة البضاعة المباعة (COGS) | 600 | |
| المخزون (Inventory) | | 600 |

#### عند التحصيل لاحقاً (Payment Collection):
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| الصندوق/البنك (Cash/Bank) | 1,150 | |
| العملاء/المدينون (Accounts Receivable) | | 1,150 |

---

### 2.3 الخصومات (Discounts)

#### خصم على السعر (Sales Discount) - خصم 10% على بيع 1,000 ريال

| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| الصندوق (Cash) | 1,035 | |
| خصم المبيعات (Sales Discount) ⚠️ Contra-Revenue | 100 | |
| ضريبة VAT المستحقة (VAT Payable) | | 135 |
| إيراد المبيعات (Sales Revenue) | | 1,000 |

> **ملاحظة مهمة:** خصم المبيعات (Sales Discount) حساب عكسي (Contra-Revenue) يُسجّل في الجانب المدين ويقلل الإيراد الصافي.

---

### 2.4 المرتجعات (Sales Returns / Refunds)

#### مرتجع نقدي - إرجاع بضاعة بـ 500 ريال + VAT 75

**القيد الأول: عكس الإيراد**
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| مرتجع المبيعات (Sales Returns & Allowances) ⚠️ Contra-Revenue | 500 | |
| ضريبة VAT المستحقة (VAT Payable) | 75 | |
| الصندوق (Cash) | | 575 |

**القيد الثاني: إعادة المخزون**
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| المخزون (Inventory) | 300 | |
| تكلفة البضاعة المباعة (COGS) | | 300 |

---

### 2.5 الإلغاء (Void Transaction)

الـ Void يختلف عن الـ Return:
- **Void** = إلغاء العملية بالكامل قبل إقفال الوردية (نفس اليوم عادةً)
- **Return** = إرجاع بعد الإقفال

محاسبياً: Void = عكس القيد الأصلي بالكامل (Reversal Entry)

| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| إيراد المبيعات (Sales Revenue) | XXX | |
| ضريبة VAT المستحقة (VAT Payable) | XX | |
| الصندوق/العملاء (Cash/AR) | | XXX + XX |
| المخزون (Inventory) | XX | |
| تكلفة البضاعة المباعة (COGS) | | XX |

> **يتطلب صلاحية مدير (Manager Authorization)** لعملية Void

---

### 2.6 الضريبة/VAT في معاملات POS

#### عند البيع (Collecting VAT):
- VAT تُجمع من العميل وتُسجّل كـ **Liability** (التزام)
- Credit: VAT Payable (ضريبة مستحقة الدفع)

#### عند الشراء (Input VAT):
- VAT تُدفع للمورد وتُسجّل كـ **Asset** (أصل/مسترد)
- Debit: VAT Receivable / Input VAT (ضريبة على المشتريات)

#### عند التسوية للهيئة الضريبية (VAT Settlement):
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| ضريبة VAT المستحقة (VAT Payable - Output) | XXX | |
| ضريبة VAT على المشتريات (VAT Receivable - Input) | | XXX |
| البنك (Bank) - الفرق | الفرق | الفرق |

---

### 2.7 ملخص الحسابات المحاسبية المطلوبة في نظام POS

```
Chart of Accounts for POS:
├── Assets (أصول)
│   ├── Cash in Drawer (الصندوق)
│   ├── Accounts Receivable (العملاء)
│   ├── Inventory (المخزون)
│   └── VAT Receivable/Input VAT (ضريبة المشتريات)
├── Liabilities (التزامات)
│   ├── VAT Payable/Output VAT (ضريبة المبيعات)
│   └── Customer Deposits (دفعات العملاء المقدمة)
├── Equity (حقوق الملكية)
├── Revenue (إيرادات)
│   ├── Sales Revenue (إيراد المبيعات)
│   └── (-) Sales Returns & Allowances (مرتجع المبيعات) [Contra]
├── Cost of Goods Sold (تكلفة البضاعة المباعة)
│   └── COGS
└── Expenses (مصروفات)
    ├── Sales Discount (خصم المبيعات) [Contra-Revenue]
    └── Cash Over/Short (عجز/زيادة الصندوق)
```

---

## 3. نظام الوردية (Shift System)

### 3.1 ما هي الوردية؟ (What is a Shift?)

الوردية (Shift) هي **فترة زمنية محددة** يعمل فيها الكاشير على نقطة بيع معينة. تبدأ بفتح الوردية (Opening Shift) وتنتهي بإقفالها (Closing Shift). الهدف الأساسي هو **التحكم في النقدية (Cash Control)** ومساءلة الكاشير.

### 3.2 دورة حياة الوردية (Shift Lifecycle)

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   OPEN       │───▶│  ACTIVE      │───▶│  BLIND CLOSE │───▶│  CLOSED      │
│  فتح الوردية │    │  نشطة        │    │  إقفال أعمى  │    │  مقفلة       │
└─────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
   Opening           Transactions       Count Cash          Z-Report
   Cash Declare      Sales/Returns      No totals shown     Final Settlement
```

### 3.3 فتح الوردية (Opening a Shift)

**الإجراءات:**
1. الكاشير يسجل الدخول (Login)
2. يُدخل مبلغ افتتاح الصندوق (Opening Cash / Float)
3. يُحدد Cash Box/Drawer المرتبط
4. يُنشئ سجل الوردية في النظام

**القيد المحاسبي لفتح الوردية:**
> ⚠️ **مهم:** فتح الوردية لا يُنشئ قيد محاسبي! المبلغ الافتتاحي هو فقط إقرار (Declaration) بأن الصندوق يحتوي على هذا المبلغ.

```dart
// No Journal Entry for Opening Shift
// فقط سجل داخلي: Shift Opening Record
{
  shift_id: "SH-2024-001",
  cashier_id: "C-001",
  cash_box_id: "CB-01",
  opening_amount: 500.00,
  opening_time: "2024-01-15 08:00",
  status: "OPEN"
}
```

### 3.4 المعاملات خلال الوردية (Transactions During Shift)

كل معاملة تُضاف لسجل الوردية:
```
Shift Running Totals:
├── Total Sales (Cash)     = 5,000
├── Total Sales (Card)     = 3,000
├── Total Sales (Credit)   = 1,000
├── Total Returns          = (500)
├── Total Discounts        = (200)
├── Cash In (Additions)    = 300
├── Cash Out (Withdrawals) = 1,000
└── Expected Cash          = 500 + 5,000 - 500 + 300 - 1,000 = 4,300
```

**حساب النقدية المتوقعة (Expected Cash):**
```
Expected Cash = Opening Amount 
              + Cash Sales 
              - Cash Returns/Refunds 
              + Cash In (Additions) 
              - Cash Out (Withdrawals/Pay-outs)
```

### 3.5 إقفال الوردية (Closing a Shift)

**الخطوات:**
1. إيقاف إمكانية إجراء معاملات جديدة
2. عدّ النقدية الفعلية في الصندوق (Physical Cash Count)
3. مقارنة الفعلي مع المتوقع (Actual vs Expected)
4. تسجيل الفرق (Over/Short)

**حساب الفرق:**
```
Over/Short = Actual Cash Count - Expected Cash
             ┌──────────────────────────────────┐
             │  Over (زيادة): Actual > Expected │
             │  Short (عجز): Actual < Expected  │
             └──────────────────────────────────┘
```

### 3.6 X-Report مقابل Z-Report

| الخاصية | X-Report | Z-Report |
|---|---|---|
| **التوقيت** | في أي وقت أثناء الوردية | عند إقفال الوردية فقط |
| **الغرض** | مراجعة مؤقتة (Snapshot) | التسوية النهائية (Settlement) |
| **إعادة العدّاد** | لا (لا يُصفّر) | نعم (يُصفّر العدّادات) |
| **إغلاق الوردية** | لا يُغلق الوردية | يُغلق الوردية نهائياً |
| **الاستخدام** | فحص سريع أثناء العمل | التسوية في نهاية اليوم/الوردية |
| **محتوى التقرير** | المبيعات/المدفوعات/الضرائب | نفس + العجز/الزيادة + الإقفال |

**محتوى X-Report / Z-Report:**
```
┌──────────────────────────────────────────────┐
│              Z-REPORT / X-REPORT              │
├──────────────────────────────────────────────┤
│ Branch: الفرع الرئيسي                          │
│ Cash Box: CB-01                               │
│ Cashier: أحمد محمد                             │
│ Shift: SH-2024-001                            │
│ Opened: 2024-01-15 08:00                      │
│ Closed: 2024-01-15 20:00                      │
├──────────────────────────────────────────────┤
│ SALES SUMMARY:                                │
│   Total Sales:          9,000.00              │
│   Cash Sales:           5,000.00              │
│   Card Sales:           3,000.00              │
│   Credit Sales:         1,000.00              │
├──────────────────────────────────────────────┤
│ RETURNS & DISCOUNTS:                           │
│   Returns:             (500.00)               │
│   Discounts:           (200.00)               │
│   Void Transactions:        0.00              │
├──────────────────────────────────────────────┤
│ TAX:                                          │
│   VAT Collected:       1,245.00               │
├──────────────────────────────────────────────┤
│ CASH DRAWER:                                   │
│   Opening Amount:        500.00               │
│   Cash Sales:          5,000.00               │
│   Cash Returns:          (500.00)             │
│   Cash In:                300.00              │
│   Cash Out:             (1,000.00)            │
│   Expected Cash:        4,300.00              │
│   Actual Cash:          4,250.00              │
│   Over/Short:             (50.00) ← عجز      │
├──────────────────────────────────────────────┤
│ TRANSACTION COUNT:                             │
│   Total Transactions:        87               │
│   Returns:                    3               │
│   Voids:                      1               │
└──────────────────────────────────────────────┘
```

### 3.7 العجز والزيادة في الصندوق (Cash Over/Short)

**مثال:** المتوقع 4,300 ريال، الفعلي 4,250 ريال → عجز 50 ريال

#### قيد عجز الصندوق (Cash Shortage):
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| عجز/زيادة الصندوق (Cash Over/Short) | 50 | |
| الصندوق (Cash in Drawer) | | 50 |

#### قيد زيادة الصندوق (Cash Overage):
| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| الصندوق (Cash in Drawer) | XX | |
| عجز/زيادة الصندوق (Cash Over/Short) | | XX |

### 3.8 العلاقة بين الورديات وصناديق النقدية (Shift ↔ Cash Box)

```
┌──────────────────┐         ┌──────────────────┐
│    Cash Box       │◀───────│     Shift         │
│  (صندوق نقدية)    │  1:1    │   (وردية)         │
├──────────────────┤ أو 1:Many├──────────────────┤
│ id: CB-01        │         │ id: SH-001       │
│ name: "Register 1"│        │ cash_box_id: CB-01│
│ location: "Branch A"│       │ cashier_id: C-001 │
│ status: ACTIVE   │         │ status: OPEN      │
└──────────────────┘         └──────────────────┘

الأنماط الممكنة:
1. Shift per Cashier (وردية لكل كاشير) - الأكثر شيوعاً
2. Shared Shift (وردية مشتركة) - عدة كاشيرين على نفس الصندوق
```

### 3.9 قيد إقفال الوردية (Shift Closing Journal Entry)

عند إقفال الوردية، يتم تحويل النقدية من الصندوق إلى الخزينة/البنك:

| الحساب (Account) | مدين (Debit) | دائن (Credit) |
|---|---|---|
| البنك/الخزينة (Bank/Petty Cash) | 4,250 | |
| الصندوق (Cash in Drawer) | | 4,250 |

---

## 4. نظام الكاشير (Cashier System)

### 4.1 تسجيل دخول/خروج الكاشير (Cashier Login/Logout)

```
Cashier Authentication Flow:
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  PIN/Password│────▶│ Verify       │────▶│ Check Active │────▶│ Open/Resume  │
│  أو بصمة     │     │ Credentials  │     │ Shift?       │     │ Shift        │
└─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

**أنماط الدخول:**
- **PIN Code** (الأكثر شيوعاً في POS - سريع)
- **Username + Password** (أكثر أماناً)
- **Biometric** (بصمة الإصبع - أقل شيوعاً لكن آمن)
- **RFID Card** (بطاقة الموظف)

**منطق الدخول:**
```
Cashier Login →
  ├── Has Active Shift? → Resume that shift
  ├── No Active Shift? → 
  │   ├── Has Unassigned Cash Box? → Create new shift
  │   └── No available Cash Box? → Error: "No available register"
  └── Already logged in elsewhere? → Error: "Already active on another register"
```

### 4.2 صلاحيات الكاشير (Cashier Permissions)

| الصلاحية (Permission) | الكاشير | المشرف | المدير |
|---|---|---|---|
| عملية بيع (Sale) | ✅ | ✅ | ✅ |
| مرتجع (Return) | ❌ | ✅ | ✅ |
| إلغاء عملية (Void) | ❌ | ✅ | ✅ |
| خصم (Discount) | خصم محدود | ✅ | ✅ |
| فتح الصندوق (Open Drawer) | ❌ | ✅ | ✅ |
| X-Report | ✅ | ✅ | ✅ |
| Z-Report / إقفال وردية | ❌ | ✅ | ✅ |
| تعديل سعر | ❌ | ✅ | ✅ |
| إضافة نقدية للصندوق (Cash In) | ❌ | ✅ | ✅ |
| سحب نقدية (Cash Out) | ❌ | ✅ | ✅ |
| إنشاء منتج جديد | ❌ | ❌ | ✅ |
| إدارة المستخدمين | ❌ | ❌ | ✅ |

**تطبيق الصلاحيات (Role-Based Access Control - RBAC):**
```dart
enum POSPermission {
  makeSale,
  processReturn,
  voidTransaction,
  applyDiscount,
  openDrawer,
  viewXReport,
  closeShift,
  adjustPrice,
  cashIn,
  cashOut,
  manageProducts,
  manageUsers,
}

class CashierRole {
  final String name;
  final Set<POSPermission> permissions;
  
  bool hasPermission(POSPermission permission) =>
      permissions.contains(permission);
}

// Predefined Roles
final cashierRole = CashierRole(
  name: 'Cashier',
  permissions: {POSPermission.makeSale, POSPermission.viewXReport},
);

final supervisorRole = CashierRole(
  name: 'Supervisor',
  permissions: {
    POSPermission.makeSale, POSPermission.processReturn,
    POSPermission.voidTransaction, POSPermission.applyDiscount,
    POSPermission.openDrawer, POSPermission.viewXReport,
    POSPermission.closeShift, POSPermission.adjustPrice,
    POSPermission.cashIn, POSPermission.cashOut,
  },
);

final managerRole = CashierRole(
  name: 'Manager',
  permissions: POSPermission.values.toSet(), // جميع الصلاحيات
);
```

### 4.3 ربط الكاشير بالوردية والصندوق

```
Cashier Assignment Models:

Model 1: Dedicated Shift (الأكثر أماناً)
┌─────────┐    ┌─────────┐    ┌──────────┐
│ Cashier │───▶│  Shift  │───▶│ Cash Box │
│  أحمد   │    │ SH-001  │    │  CB-01   │
└─────────┘    └─────────┘    └──────────┘
(كاشير واحد = وردية واحدة = صندوق واحد)

Model 2: Shared Shift (وردية مشتركة)
┌─────────┐    ┌─────────┐
│ Cashier │───▶│         │
│  أحمد   │    │  Shift  │───▶│ Cash Box │
├─────────┤    │ SH-001  │    │  CB-01   │
│ Cashier │───▶│         │
│  سارة   │    └─────────┘    └──────────┘
└─────────┘
(عدة كاشيرين = وردية واحدة = صندوق واحد)
→ يتطلب صلاحية "Allow Multiple Shift Logon"

Model 3: Multiple Shifts per Cash Box (الأكثر شيوعاً في التجزئة)
┌─────────┐    ┌─────────┐
│ Shift 1 │    │ SH-001  │──┐
│ (صباحاً) │    ├─────────┤  ├──▶│ Cash Box │
│ أحمد    │    │ SH-002  │──┘    │  CB-01   │
└─────────┘    └─────────┘     └──────────┘
┌─────────┐    ┌─────────┐
│ Shift 2 │    │ SH-003  │────────▶│ Cash Box │
│ (مساءً)  │    └─────────┘         │  CB-01   │
│ سارة    │                        └──────────┘
└─────────┘
```

### 4.4 تتبع أداء الكاشير (Cashier Performance Tracking)

```
Cashier Performance Metrics:
├── عدد المعاملات (Transaction Count)
├── إجمالي المبيعات (Total Sales Amount)
├── متوسط قيمة المعاملة (Average Transaction Value)
├── معدل العجز/الزيادة (Over/Short Rate)
│   └── (Total Over/Short) / (Total Cash Sales) × 100
├── عدد المرتجعات المعالجة (Return Count)
├── عدد الإلغاءات (Void Count)
├── سرعة المعاملة (Transaction Speed - items/min)
└── وقت العمل الفعلي (Active Working Time)
```

---

## 5. ماسح الباركود في Flutter (Barcode Scanner)

### 5.1 مقارنة الحزم المتاحة (Package Comparison)

| الحزمة (Package) | النوع | 1D Barcodes | 2D Barcodes | المنصات | التقييم |
|---|---|---|---|---|---|
| **mobile_scanner** | ML Kit (Google) | ✅ EAN-13, UPC-A, Code128, Code39 | ✅ QR, DataMatrix, PDF417 | Android + iOS | ⭐⭐⭐⭐⭐ الأفضل |
| **google_mlkit_barcode_scanning** | ML Kit (Google) | ✅ نفس mobile_scanner | ✅ نفس mobile_scanner | Android + iOS | ⭐⭐⭐⭐ |
| **flutter_zxing** | ZXing (Open Source) | ✅ Code128, EAN, UPC | ✅ QR | Android + iOS | ⭐⭐⭐ |
| **qr_code_scanner** | ❌ مهمل (Deprecated) | - | - | - | ❌ لا تستخدم |
| **barcode_scan2** | ZXing | ✅ | ✅ | Android + iOS | ⭐⭐⭐ |
| **scanbot_sdk** | Commercial | ✅ الكل | ✅ الكل | Android + iOS | ⭐⭐⭐⭐⭐ (مدفوع) |

### 5.2 التوصية: `mobile_scanner`

**لماذا mobile_scanner هو الأفضل؟**
1. مبني على Google ML Kit - دقة عالية جداً
2. يدعم جميع أنواع الباركود 1D و 2D
3. سرعة مسح ممتازة (Real-time Detection)
4. صيانة نشطة (Active Maintenance) - آخر إصدار 2025
5. سهل التكامل مع Flutter
6. مجاني ومفتوح المصدر
7. يدعم التحكم في Camera (Flash, Zoom)

### 5.3 أنواع الباركود المدعومة (Supported Barcode Formats)

```
1D Barcodes (الأكثر استخداماً في التجزئة):
├── EAN-13    → المنتجات العالمية (الأكثر شيوعاً عالمياً) - 13 رقم
├── EAN-8     → المنتجات الصغيرة - 8 أرقام
├── UPC-A     → المنتجات الأمريكية/الكندية - 12 رقم
├── UPC-E     → نسخة مضغوطة من UPC-A - 6 أرقام
├── Code 128  → الاستخدام الصناعي/اللوجستي - عالي الكثافة
├── Code 39   → المنتجات الصناعية - أحرف+أرقام
├── Code 93   → أقل شيوعاً
├── ITF       → الشحن والتعبئة - أرقام فقط
├── Codabar   → المكتبات/المختبرات/بنوك الدم
└── RSS       → المنتجات الطازجة/المواد الغذائية

2D Barcodes:
├── QR Code   → المدفوعات/الروابط/القوائم
├── DataMatrix → الصناعة/الصحة/الإلكترونيات
├── PDF417    → بطاقات الهوية/جوازات السفر
└── Aztec     → تذاكر الطيران/النقل
```

### 5.4 كود التنفيذ مع Flutter (Implementation)

```dart
// pubspec.yaml
dependencies:
  mobile_scanner: ^6.0.3

// barcode_scanner_page.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: [                          // تحديد أنواع الباركود المطلوبة
      BarcodeFormat.ean13,              // الأكثر شيوعاً في التجزئة
      BarcodeFormat.upcA,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,             // للمدفوعات
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (BarcodeCapture capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  final String code = barcode.rawValue!;
                  final BarcodeFormat format = barcode.format;
                  
                  // إرجاع النتيجة للشاشة السابقة
                  Navigator.pop(context, {
                    'barcode': code,
                    'format': format.name,
                  });
                }
              }
            },
          ),
          // Scanner overlay for better UX
          _buildScannerOverlay(),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(0.5),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Container(
              height: 200,
              width: 300,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
```

### 5.5 التكامل مع POS (POS Integration)

```dart
// pos_service.dart
class POSService {
  final ProductRepository _productRepo;
  final AccountingService _accountingService;
  
  // البحث عن منتج بالباركود وإضافته للسلة
  Future<CartItem?> scanAndAddToCart(String barcode) async {
    final product = await _productRepo.findByBarcode(barcode);
    if (product == null) {
      // المنتج غير موجود - عرض خيار إنشاء منتج جديد
      return null;
    }
    
    // التحقق من المخزون
    if (product.stockQuantity <= 0) {
      throw Exception('المنتج غير متوفر في المخزون');
    }
    
    return CartItem(
      productId: product.id,
      name: product.name,
      price: product.sellingPrice,
      costPrice: product.costPrice,    // لتكلفة البضاعة المباعة
      vatRate: product.vatRate,         // نسبة الضريبة
      quantity: 1,
      barcode: barcode,
    );
  }
  
  // إتمام عملية البيع وإنشاء القيود المحاسبية
  Future<SaleResult> completeSale(Sale sale) async {
    // 1. حفظ عملية البيع
    await _saleRepo.save(sale);
    
    // 2. إنشاء القيد المحاسبي للإيراد
    final revenueEntry = _accountingService.createRevenueEntry(sale);
    
    // 3. إنشاء القيد المحاسبي لتكلفة البضاعة المباعة
    final cogsEntry = _accountingService.createCOGSEntry(sale);
    
    // 4. تحديث المخزون
    for (final item in sale.items) {
      await _productRepo.decrementStock(item.productId, item.quantity);
    }
    
    // 5. تحديث إجماليات الوردية
    await _shiftService.updateShiftTotals(sale);
    
    return SaleResult(
      sale: sale,
      revenueEntry: revenueEntry,
      cogsEntry: cogsEntry,
    );
  }
}

// استخدام الماسح في شاشة POS
class POSScreen extends StatelessWidget {
  Future<void> _scanBarcode(BuildContext context) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    
    if (result != null) {
      final barcode = result['barcode'] as String;
      final format = result['format'] as String;
      
      // البحث عن المنتج وإضافته للسلة
      final cartItem = await posService.scanAndAddToCart(barcode);
      if (cartItem != null) {
        cartBloc.add(AddToCart(cartItem));
      } else {
        // عرض رسالة "منتج غير موجود"
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المنتج غير موجود')),
        );
      }
    }
  }
}
```

---

## 6. الهيكل المقترح للتطبيق (Proposed App Architecture)

### 6.1 نموذج البيانات (Data Models)

```dart
// ==================== CORE MODELS ====================

// 1. Shift Model
class Shift {
  String id;
  String cashierId;
  String cashBoxId;
  String branchId;
  double openingAmount;
  double? closingAmount;         // المبلغ الفعلي المعدود
  double? expectedAmount;        // المبلغ المتوقع حسب النظام
  double? overShortAmount;       // الفرق (زيادة/عجز)
  DateTime openedAt;
  DateTime? closedAt;
  ShiftStatus status;            // OPEN, BLIND_CLOSE, CLOSED
  Map<String, double> totals;    // إجماليات الوردية
}

// 2. Cash Box Model
class CashBox {
  String id;
  String name;
  String branchId;
  String? currentShiftId;
  CashBoxStatus status;          // ACTIVE, INACTIVE
}

// 3. Cashier Model  
class Cashier {
  String id;
  String userId;
  String name;
  String pinCode;                // مشفر (Hashed)
  String roleId;
  String? currentShiftId;
  String? assignedCashBoxId;
  bool isActive;
}

// 4. Cashier Role & Permissions
class CashierRole {
  String id;
  String name;                   // Cashier, Supervisor, Manager
  Set<POSPermission> permissions;
}

enum POSPermission {
  makeSale, processReturn, voidTransaction,
  applyDiscount, openDrawer, viewXReport,
  closeShift, adjustPrice, cashIn, cashOut,
  manageProducts, manageUsers,
}

// 5. POS Transaction Model
class POSTransaction {
  String id;
  String shiftId;
  String cashierId;
  String cashBoxId;
  TransactionType type;          // SALE, RETURN, VOID
  PaymentMethod payment;         // CASH, CARD, CREDIT, SPLIT
  List<LineItem> items;
  double subtotal;               // قبل الخصم والضريبة
  double discountAmount;
  double vatAmount;
  double totalAmount;            // المبلغ النهائي
  double amountPaid;
  double changeAmount;           // الباقي
  String? customerId;
  String? journalEntryId;        // ربط بالقيد المحاسبي
  String? voidReason;            // سبب الإلغاء
  String? voidedBy;              // من ألغى العملية
  DateTime createdAt;
  TransactionStatus status;      // PENDING, COMPLETED, VOIDED
}

// 6. Line Item Model
class LineItem {
  String productId;
  String productName;
  String? barcode;
  double quantity;
  String unit;                   // وحدة القياس (قطعة، كيلو، إلخ)
  double unitPrice;
  double discountAmount;
  double vatRate;                // نسبة الضريبة (مثلاً 0.15)
  double vatAmount;
  double totalAmount;
  double costPrice;              // لتكلفة البضاعة المباعة (COGS)
}

// 7. Journal Entry Model (Double-Entry)
class JournalEntry {
  String id;
  String? transactionId;         // ربط بمعاملة POS
  String? shiftId;
  String description;
  String reference;              // رقم مرجعي
  DateTime date;
  List<JournalLine> lines;
  JournalEntryStatus status;     // DRAFT, POSTED
  DateTime createdAt;
  String createdBy;
}

class JournalLine {
  String accountId;
  String accountCode;            // كود الحساب
  String accountName;
  double debit;
  double credit;
  String? description;
}

// 8. Shift Totals (إجماليات الوردية)
class ShiftTotals {
  double cashSales;
  double cardSales;
  double creditSales;
  double totalSales;
  double totalReturns;
  double totalDiscounts;
  double totalVAT;
  int transactionCount;
  int returnCount;
  int voidCount;
  double cashIn;                 // إضافات نقدية
  double cashOut;                // سحوبات نقدية
}
```

### 6.2 تدفق العمليات الكامل (Complete Operation Flow)

```
┌─────────────────────────────────────────────────────────────┐
│                    POS Transaction Flow                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Cashier Login (PIN/Password/Biometric)                    │
│     └──▶ Check Active Shift → Resume or Create New           │
│                                                               │
│  2. Open Shift (if new)                                       │
│     ├──▶ Select Cash Box                                      │
│     ├──▶ Declare Opening Cash Amount (Float)                  │
│     └──▶ Shift Status → OPEN                                  │
│     ⚠️ No Journal Entry created                               │
│                                                               │
│  3. Scan Barcode / Search Product                             │
│     ├──▶ mobile_scanner → Decode Barcode                      │
│     ├──▶ Lookup Product in Database                           │
│     ├──▶ Check Stock Availability                             │
│     └──▶ Add to Cart with Price + VAT                         │
│                                                               │
│  4. Complete Sale                                              │
│     ├──▶ Calculate Subtotal (sum of items)                    │
│     ├──▶ Apply Discounts (check permission first)             │
│     ├──▶ Calculate VAT per item                                │
│     ├──▶ Calculate Total (subtotal - discount + VAT)          │
│     ├──▶ Process Payment (Cash/Card/Credit/Split)             │
│     ├──▶ Calculate Change (for cash payments)                 │
│     │                                                          │
│     ├──▶ 🔴 Create Journal Entry #1: Revenue                  │
│     │     Debit: Cash/AR = Total Amount                       │
│     │     Credit: Sales Revenue = Subtotal - Discount         │
│     │     Credit: VAT Payable = VAT Amount                    │
│     │                                                          │
│     ├──▶ 🔴 Create Journal Entry #2: COGS                     │
│     │     Debit: COGS = Sum of cost prices                    │
│     │     Credit: Inventory = Sum of cost prices              │
│     │                                                          │
│     ├──▶ 📦 Update Inventory (decrement quantities)           │
│     └──▶ 📊 Update Shift Totals                               │
│                                                               │
│  5. Handle Returns/Voids (check permission!)                  │
│     ├──▶ Return: Create reversal entries                      │
│     │     Debit: Sales Returns = amount                       │
│     │     Debit: VAT Payable = VAT on return                  │
│     │     Credit: Cash/AR = total                             │
│     │     Debit: Inventory = cost                             │
│     │     Credit: COGS = cost                                 │
│     │                                                          │
│     └──▶ Void: Full reversal of original entry                │
│           (Requires manager authorization)                    │
│                                                               │
│  6. Close Shift                                                │
│     ├──▶ Stop accepting new transactions                      │
│     ├──▶ Count Physical Cash in Drawer                        │
│     ├──▶ Calculate Expected Cash                              │
│     │     Expected = Opening + Cash Sales - Cash Returns      │
│     │               + Cash In - Cash Out                      │
│     ├──▶ Calculate Over/Short                                 │
│     │     Difference = Actual - Expected                      │
│     ├──▶ 🔴 Create Journal Entry: Over/Short (if any)         │
│     │     Shortage: Debit Cash Over/Short, Credit Cash        │
│     │     Overage: Debit Cash, Credit Cash Over/Short         │
│     ├──▶ 🔴 Create Journal Entry: Cash Transfer               │
│     │     Debit: Bank/Petty Cash                              │
│     │     Credit: Cash in Drawer                              │
│     ├──▶ Generate Z-Report                                    │
│     └──▶ Shift Status → CLOSED                                │
│                                                               │
│  7. Cashier Logout                                             │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. ملخص التقنيات والحزم الموصى بها (Recommended Stack)

| المكون | التقنية/الحزمة | الإصدار |
|---|---|---|
| Framework | Flutter | 3.x |
| Barcode Scanner | `mobile_scanner` | ^6.0.3 |
| State Management | Riverpod / Bloc | latest |
| Local Database | SQLite (drift) | latest |
| Backend API | REST API (Dart Shelf) | latest |
| Accounting Engine | Custom Double-Entry Module | - |
| PDF Reports | `pdf` package | latest |
| Thermal Printer | `esc_pos_utils` + `printing` | latest |
| Authentication | Local PIN + `local_auth` (Biometric) | latest |
| Encryption | `encrypt` package (PIN storage) | latest |

---

## 8. ملاحظات مهمة للتطبيق (Important Implementation Notes)

1. **عزل الورديات:** كل وردية مستقلة محاسبياً - لا يمكن لعملية أن تنتقل بين ورديتين
2. **ترابط البيانات:** كل Transaction مرتبط بـ Shift و Cashier و Cash Box و Journal Entry
3. **عدم الحذف أبداً:** لا تُحذف المعاملات أبداً - الـ Void = Reversal Entry وليس حذف
4. **التدقيق (Audit Trail):** كل عملية تُسجّل مع من قام بها ومتى ولماذا
5. **الضريبة التلقائية:** VAT تُحسب تلقائياً عند كل معاملة ولا يمكن تعديلها يدوياً
6. **التسوية التلقائية:** إقفال الوردية يحسب تلقائياً الفرق (Over/Short) ويُنشئ القيد المناسب
7. **الصلاحيات الإلزامية:** كل عملية حساسة (Void, Return, Discount, Open Drawer) تتطلب صلاحية مناسبة
8. **Offline Support:** النظام يجب أن يعمل بدون إنترنت مع مزامنة لاحقة
9. **المنتج غير المعروف:** عند مسح باركود غير موجود، يجب عرض خيار إنشاء منتج جديد سريعاً
10. **السلة الذكية:** مسح نفس الباركود مرة أخرى يزيد الكمية بدلاً من إضافة سطر جديد

---

*تم إعداد هذا التقرير بناءً على بحث شامل في المصادر المحاسبية وتقنيات Flutter والممارسات العالمية في أنظمة POS*

*المصادر الرئيسية:*
- *Patriot Software - Sales Journal Entries & Inventory Accounting*
- *NetSuite - Double-Entry Accounting & Sales Tax Payable*
- *Microsoft Dynamics 365 - Shift and Cash Drawer Management*
- *Mobile Transaction - X-Report vs Z-Report*
- *Scanbot SDK - Flutter Barcode Scanner Libraries Comparison*
- *Oracle - Journal Entry with VAT Tax*
- *Xero & Salesforce - Double-Entry Bookkeeping*
