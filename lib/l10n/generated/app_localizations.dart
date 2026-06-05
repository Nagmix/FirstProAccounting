import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'الأول برو المحاسبي'**
  String get appName;

  /// No description provided for @dashboard.
  ///
  /// In ar, this message translates to:
  /// **'لوحة المعلومات'**
  String get dashboard;

  /// No description provided for @pos.
  ///
  /// In ar, this message translates to:
  /// **'نقطة البيع'**
  String get pos;

  /// No description provided for @more.
  ///
  /// In ar, this message translates to:
  /// **'المزيد'**
  String get more;

  /// No description provided for @sales.
  ///
  /// In ar, this message translates to:
  /// **'المبيعات'**
  String get sales;

  /// No description provided for @purchases.
  ///
  /// In ar, this message translates to:
  /// **'المشتريات'**
  String get purchases;

  /// No description provided for @expenses.
  ///
  /// In ar, this message translates to:
  /// **'المصروفات'**
  String get expenses;

  /// No description provided for @invoices.
  ///
  /// In ar, this message translates to:
  /// **'الفواتير'**
  String get invoices;

  /// No description provided for @products.
  ///
  /// In ar, this message translates to:
  /// **'المنتجات'**
  String get products;

  /// No description provided for @customers.
  ///
  /// In ar, this message translates to:
  /// **'العملاء'**
  String get customers;

  /// No description provided for @suppliers.
  ///
  /// In ar, this message translates to:
  /// **'الموردون'**
  String get suppliers;

  /// No description provided for @reports.
  ///
  /// In ar, this message translates to:
  /// **'التقارير'**
  String get reports;

  /// No description provided for @settings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get settings;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة'**
  String get add;

  /// No description provided for @search.
  ///
  /// In ar, this message translates to:
  /// **'بحث'**
  String get search;

  /// No description provided for @total.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get total;

  /// No description provided for @subtotal.
  ///
  /// In ar, this message translates to:
  /// **'المجموع الفرعي'**
  String get subtotal;

  /// No description provided for @discount.
  ///
  /// In ar, this message translates to:
  /// **'الخصم'**
  String get discount;

  /// No description provided for @tax.
  ///
  /// In ar, this message translates to:
  /// **'الضريبة'**
  String get tax;

  /// No description provided for @quantity.
  ///
  /// In ar, this message translates to:
  /// **'الكمية'**
  String get quantity;

  /// No description provided for @price.
  ///
  /// In ar, this message translates to:
  /// **'السعر'**
  String get price;

  /// No description provided for @balance.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد'**
  String get balance;

  /// No description provided for @cash.
  ///
  /// In ar, this message translates to:
  /// **'نقدي'**
  String get cash;

  /// No description provided for @credit.
  ///
  /// In ar, this message translates to:
  /// **'آجل'**
  String get credit;

  /// No description provided for @paid.
  ///
  /// In ar, this message translates to:
  /// **'مدفوع'**
  String get paid;

  /// No description provided for @unpaid.
  ///
  /// In ar, this message translates to:
  /// **'غير مدفوع'**
  String get unpaid;

  /// No description provided for @partial.
  ///
  /// In ar, this message translates to:
  /// **'مدفوع جزئياً'**
  String get partial;

  /// No description provided for @saleInvoice.
  ///
  /// In ar, this message translates to:
  /// **'فاتورة مبيعات'**
  String get saleInvoice;

  /// No description provided for @purchaseInvoice.
  ///
  /// In ar, this message translates to:
  /// **'فاتورة مشتريات'**
  String get purchaseInvoice;

  /// No description provided for @returnInvoice.
  ///
  /// In ar, this message translates to:
  /// **'فاتورة مرتجع'**
  String get returnInvoice;

  /// No description provided for @trialBalance.
  ///
  /// In ar, this message translates to:
  /// **'ميزان المراجعة'**
  String get trialBalance;

  /// No description provided for @incomeStatement.
  ///
  /// In ar, this message translates to:
  /// **'قائمة الدخل'**
  String get incomeStatement;

  /// No description provided for @balanceSheet.
  ///
  /// In ar, this message translates to:
  /// **'قائمة المركزية المالية'**
  String get balanceSheet;

  /// No description provided for @noData.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد بيانات'**
  String get noData;

  /// No description provided for @loading.
  ///
  /// In ar, this message translates to:
  /// **'جاري التحميل...'**
  String get loading;

  /// No description provided for @errorLoadingData.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ أثناء تحميل البيانات'**
  String get errorLoadingData;

  /// No description provided for @errorSaving.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ أثناء الحفظ'**
  String get errorSaving;

  /// No description provided for @confirmDelete.
  ///
  /// In ar, this message translates to:
  /// **'هل أنت متأكد من الحذف؟'**
  String get confirmDelete;

  /// No description provided for @yes.
  ///
  /// In ar, this message translates to:
  /// **'نعم'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In ar, this message translates to:
  /// **'لا'**
  String get no;

  /// No description provided for @ok.
  ///
  /// In ar, this message translates to:
  /// **'حسناً'**
  String get ok;

  /// No description provided for @currency.
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get currency;

  /// No description provided for @date.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get date;

  /// No description provided for @description.
  ///
  /// In ar, this message translates to:
  /// **'الوصف'**
  String get description;

  /// No description provided for @notes.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات'**
  String get notes;

  /// No description provided for @account.
  ///
  /// In ar, this message translates to:
  /// **'الحساب'**
  String get account;

  /// No description provided for @accounts.
  ///
  /// In ar, this message translates to:
  /// **'الحسابات'**
  String get accounts;

  /// No description provided for @debit.
  ///
  /// In ar, this message translates to:
  /// **'مدين'**
  String get debit;

  /// No description provided for @credit2.
  ///
  /// In ar, this message translates to:
  /// **'دائن'**
  String get credit2;

  /// No description provided for @inventory.
  ///
  /// In ar, this message translates to:
  /// **'المخزون'**
  String get inventory;

  /// No description provided for @warehouses.
  ///
  /// In ar, this message translates to:
  /// **'المستودعات'**
  String get warehouses;

  /// No description provided for @categories.
  ///
  /// In ar, this message translates to:
  /// **'الفئات'**
  String get categories;

  /// No description provided for @voucherReceipt.
  ///
  /// In ar, this message translates to:
  /// **'سند قبض'**
  String get voucherReceipt;

  /// No description provided for @voucherPayment.
  ///
  /// In ar, this message translates to:
  /// **'سند صرف'**
  String get voucherPayment;

  /// No description provided for @cashTransfer.
  ///
  /// In ar, this message translates to:
  /// **'تحويل نقدي'**
  String get cashTransfer;

  /// No description provided for @currencyExchange.
  ///
  /// In ar, this message translates to:
  /// **'صرافة عملات'**
  String get currencyExchange;

  /// No description provided for @shifts.
  ///
  /// In ar, this message translates to:
  /// **'المناوبات'**
  String get shifts;

  /// No description provided for @closeShift.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق الوردية'**
  String get closeShift;

  /// No description provided for @openShift.
  ///
  /// In ar, this message translates to:
  /// **'فتح وردية'**
  String get openShift;

  /// No description provided for @fiscalYear.
  ///
  /// In ar, this message translates to:
  /// **'السنة المالية'**
  String get fiscalYear;

  /// No description provided for @closeFiscalYear.
  ///
  /// In ar, this message translates to:
  /// **'إقفال السنة المالية'**
  String get closeFiscalYear;

  /// No description provided for @backup.
  ///
  /// In ar, this message translates to:
  /// **'نسخ احتياطي'**
  String get backup;

  /// No description provided for @restore.
  ///
  /// In ar, this message translates to:
  /// **'استعادة'**
  String get restore;

  /// No description provided for @print.
  ///
  /// In ar, this message translates to:
  /// **'طباعة'**
  String get print;

  /// No description provided for @export.
  ///
  /// In ar, this message translates to:
  /// **'تصدير'**
  String get export;

  /// No description provided for @share.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة'**
  String get share;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
