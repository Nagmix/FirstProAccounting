import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/license/license_constants.dart';
import '../../../core/license/license_models.dart';
import '../../../core/license/license_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../currency_exchange/currency_exchange_screen.dart';
import '../cash_transfers/cash_transfer_screen.dart';
import '../debts/debts_screen.dart';
import 'bluetooth_printer_settings_screen.dart';
import 'widgets/settings_helpers.dart';
import 'widgets/settings_profile_section.dart';
import 'widgets/settings_data_section.dart';
import 'widgets/settings_app_lock_section.dart';

/// Professional settings screen for the FirstPro accounting app.
///
/// Organized into logical groups:
/// 1. Profile section – business name, phone, email, logo (loaded from DB)
/// 2. عام (General) – username, business name, currency, tax rate, language
/// 3. الفواتير (Invoices) – auto-numbering, prefix, auto-print, show tax
/// 4. المخزون (Inventory) – stock alerts, threshold, expiry tracking
/// 5. العرض (Display) – theme mode, font size
/// 6. الأعمال (Operations) – currency exchange, cash transfers, debt tracking
/// 7. قفل التطبيق (App Lock) – PIN toggle, set/change PIN, biometric auth
/// 8. المحاسبة (Accounting Audit) – accounting audit
/// 9. البيانات (Data) – backup, restore, export, clear data
/// 10. حول التطبيق (About) – version, rate, contact, privacy
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Profile fields (loaded from DB) ──────────────────────────────
  final _businessNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  String? _businessLogoPath;

  // ── General settings state ───────────────────────────────────────
  final _userNameController = TextEditingController();
  double _taxRate = 15.0;

  // ── Invoice settings state ───────────────────────────────────────
  bool _autoInvoiceNumber = true;
  final _invoicePrefixController = TextEditingController(text: 'INV-');
  bool _autoPrintAfterSale = false;
  bool _showTaxInInvoice = true;

  // ── Inventory settings state ─────────────────────────────────────
  bool _stockAlert = true;
  int _stockAlertThreshold = 5;
  bool _trackExpiryDate = false;

  // ── Display settings state ───────────────────────────────────────
  int _themeModeIndex = 0; // 0=فاتح, 1=ليلي, 2=تلقائي
  int _fontSizeIndex = 1; // 0=صغير, 1=متوسط, 2=كبير

  // ── App Lock settings state ──────────────────────────────────────
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  bool _isBiometricAvailable = false;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ── Auto-backup settings state ─────────────────────────────────
  bool _autoBackupEnabled = false;
  int _autoBackupFrequencyIndex = 0; // 0=يومي, 1=أسبوعي
  String? _lastBackupDate;

  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _userNameController.dispose();
    _invoicePrefixController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final refRepo = locator<ReferenceDataRepository>();
    final businessName = await refRepo.getSetting('business_name');
    final phone = await refRepo.getSetting('business_phone');
    final email = await refRepo.getSetting('business_email');
    final address = await refRepo.getSetting('business_address');
    final logoPath = await refRepo.getSetting('business_logo_path');
    final userName = await refRepo.getSetting('user_name');
    final taxRate = await refRepo.getSetting('tax_rate');
    final autoInvoice = await refRepo.getSetting('auto_invoice_number');
    final invoicePrefix = await refRepo.getSetting('invoice_prefix');
    final autoPrint = await refRepo.getSetting('auto_print_after_sale');
    final showTax = await refRepo.getSetting('show_tax_in_invoice');
    final stockAlert = await refRepo.getSetting('stock_alert');
    final stockThreshold = await refRepo.getSetting('stock_alert_threshold');
    final trackExpiry = await refRepo.getSetting('track_expiry_date');
    final themeMode = await refRepo.getSetting('theme_mode_index');
    final fontSize = await refRepo.getSetting('font_size_index');
    // Read PIN enabled from secure storage with DB fallback for migration
    String? pinEnabled = await _secureStorage.read(key: 'pin_enabled');
    if (pinEnabled == null) {
      pinEnabled = await refRepo.getSetting('pin_enabled');
      if (pinEnabled != null && pinEnabled.isNotEmpty) {
        // Migrate to secure storage
        await _secureStorage.write(key: 'pin_enabled', value: pinEnabled);
        await refRepo.deleteSetting('pin_enabled');
      }
    }
    final biometricEnabled = await refRepo.getSetting('biometric_enabled');
    final autoBackupEnabled = await refRepo.getSetting('auto_backup_enabled');
    final autoBackupFreq = await refRepo.getSetting('auto_backup_frequency');
    final lastBackup = await refRepo.getSetting('last_backup_date');

    // Check biometric availability
    bool biometricAvailable = false;
    try {
      final localAuth = LocalAuthentication();
      biometricAvailable = await localAuth.isDeviceSupported();
    } on PlatformException {
      biometricAvailable = false;
    }

    if (mounted) {
      setState(() {
        if (businessName != null) _businessNameController.text = businessName;
        if (phone != null) _phoneController.text = phone;
        if (email != null) _emailController.text = email;
        if (address != null) _addressController.text = address;
        _businessLogoPath = (logoPath != null && logoPath.isNotEmpty) ? logoPath : null;
        if (userName != null) _userNameController.text = userName;
        if (taxRate != null) _taxRate = double.tryParse(taxRate) ?? 15.0;
        if (autoInvoice != null) _autoInvoiceNumber = autoInvoice == '1';
        if (invoicePrefix != null) _invoicePrefixController.text = invoicePrefix;
        if (autoPrint != null) _autoPrintAfterSale = autoPrint == '1';
        if (showTax != null) _showTaxInInvoice = showTax == '1';
        if (stockAlert != null) _stockAlert = stockAlert == '1';
        if (stockThreshold != null) _stockAlertThreshold = int.tryParse(stockThreshold) ?? 5;
        if (trackExpiry != null) _trackExpiryDate = trackExpiry == '1';
        if (themeMode != null) _themeModeIndex = int.tryParse(themeMode) ?? 0;
        if (fontSize != null) _fontSizeIndex = int.tryParse(fontSize) ?? 1;
        _pinEnabled = pinEnabled == '1';
        _biometricEnabled = biometricEnabled == '1';
        _isBiometricAvailable = biometricAvailable;
        _autoBackupEnabled = autoBackupEnabled == '1';
        _autoBackupFrequencyIndex = autoBackupFreq == 'weekly' ? 1 : 0;
        _lastBackupDate = lastBackup;
        _isLoaded = true;
      });
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    await locator<ReferenceDataRepository>().setSetting(key, value);
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 32 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile section ────────────────────────────────
            SettingsProfileSection(
              theme: theme,
              isDark: isDark,
              businessNameController: _businessNameController,
              phoneController: _phoneController,
              emailController: _emailController,
              addressController: _addressController,
              businessLogoPath: _businessLogoPath,
              saveSetting: _saveSetting,
              onProfileUpdated: () => setState(() {}),
            ),

            const SizedBox(height: 8),

            // ── General ────────────────────────────────────────
            SettingsGroup(
              title: 'عام',
              icon: Icons.settings,
              isDark: isDark,
              children: [
                TextSetting(
                  label: 'اسم المستخدم',
                  controller: _userNameController,
                  isDark: isDark,
                  onSave: () => _saveSetting('user_name', _userNameController.text),
                ),
                TextSetting(
                  label: 'اسم النشاط التجاري',
                  controller: _businessNameController,
                  isDark: isDark,
                ),
                _buildCurrencyLink(isDark),
                _buildExchangeRatesLink(isDark),
                _buildTaxSlider(isDark),
                ReadOnlySetting(
                  label: 'اللغة',
                  value: 'العربية',
                  icon: Icons.language,
                  isDark: isDark,
                ),
              ],
            ),

            // ── Invoices ───────────────────────────────────────
            SettingsGroup(
              title: 'الفواتير',
              icon: Icons.receipt,
              isDark: isDark,
              children: [
                SwitchListTile(
                  title: const Text('رقم الفاتورة التلقائي'),
                  subtitle: const Text('توليد رقم فاتورة تلقائياً عند الإنشاء'),
                  value: _autoInvoiceNumber,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _autoInvoiceNumber = v);
                    _saveSetting('auto_invoice_number', v ? '1' : '0');
                  },
                ),
                TextSetting(
                  label: 'بادئة رقم الفاتورة',
                  controller: _invoicePrefixController,
                  isDark: isDark,
                ),
                SwitchListTile(
                  title: const Text('طباعة تلقائية بعد البيع'),
                  value: _autoPrintAfterSale,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _autoPrintAfterSale = v);
                    _saveSetting('auto_print_after_sale', v ? '1' : '0');
                  },
                ),
                SwitchListTile(
                  title: const Text('عرض الضريبة في الفاتورة'),
                  value: _showTaxInInvoice,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _showTaxInInvoice = v);
                    _saveSetting('show_tax_in_invoice', v ? '1' : '0');
                  },
                ),
                ActionTile(
                  icon: Icons.bluetooth,
                  title: 'إعدادات الطابعة البلوتوث',
                  subtitle: 'إعداد طابعة حرارية 80مم عبر البلوتوث',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BluetoothPrinterSettingsScreen()),
                  ),
                  isDark: isDark,
                ),
              ],
            ),

            // ── Inventory ──────────────────────────────────────
            SettingsGroup(
              title: 'المخزون',
              icon: Icons.inventory_2,
              isDark: isDark,
              children: [
                SwitchListTile(
                  title: const Text('تنبيه نفاد المخزون'),
                  subtitle: const Text('إشعار عند وصول كمية المنتج للحد الأدنى'),
                  value: _stockAlert,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _stockAlert = v);
                    _saveSetting('stock_alert', v ? '1' : '0');
                  },
                ),
                NumberSetting(
                  label: 'حد التنبيه',
                  value: _stockAlertThreshold,
                  onChanged: (v) {
                    setState(() => _stockAlertThreshold = v);
                    _saveSetting('stock_alert_threshold', v.toString());
                  },
                  isDark: isDark,
                ),
                SwitchListTile(
                  title: const Text('تتبع تاريخ الصلاحية'),
                  subtitle: const Text('تنبيه عند اقتراب انتهاء صلاحية المنتجات'),
                  value: _trackExpiryDate,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _trackExpiryDate = v);
                    _saveSetting('track_expiry_date', v ? '1' : '0');
                  },
                ),
                ActionTile(
                  icon: Icons.inventory,
                  title: 'سندات الجرد',
                  subtitle: 'تسوية كميات المخزون وضبط القيود المحاسبية',
                  onTap: () => Navigator.pushNamed(context, AppConstants.inventoryVoucher),
                  isDark: isDark,
                ),
              ],
            ),

            // ── Display ────────────────────────────────────────
            SettingsGroup(
              title: 'العرض',
              icon: Icons.brush,
              isDark: isDark,
              children: [
                _buildThemeModeSelector(isDark),
                _buildFontSizeSelector(isDark),
              ],
            ),

            // ── Operations (الأعمال) ────────────────────────────
            SettingsGroup(
              title: 'الأعمال',
              icon: Icons.work,
              isDark: isDark,
              children: [
                ActionTile(
                  icon: Icons.swap_horiz,
                  title: 'مصارفة عملات',
                  subtitle: 'تحويل العملات بأسعار الصرف المحددة',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CurrencyExchangeScreen()),
                  ),
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.swap_horiz,
                  title: 'تحويل بين الصناديق',
                  subtitle: 'نقل الأموال بين الصناديق والخزائن',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CashTransferScreen()),
                  ),
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.error_outline,
                  title: 'تتبع الديون',
                  subtitle: 'متابعة ديون العملاء والموردين',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DebtsScreen()),
                  ),
                  isDark: isDark,
                ),
              ],
            ),

            // ── App Lock (قفل التطبيق) ─────────────────────────
            SettingsAppLockSection(
              isDark: isDark,
              saveSetting: _saveSetting,
              pinEnabled: _pinEnabled,
              biometricEnabled: _biometricEnabled,
              isBiometricAvailable: _isBiometricAvailable,
              onPinEnabledChanged: (v) {
                setState(() => _pinEnabled = v);
              },
              onBiometricEnabledChanged: (v) {
                setState(() => _biometricEnabled = v);
              },
            ),

            // ── Accounting Audit ────────────────────────────────
            SettingsGroup(
              title: 'المحاسبة',
              icon: Icons.verified_user,
              isDark: isDark,
              children: [
                ActionTile(
                  icon: Icons.search,
                  title: 'التدقيق المحاسبي',
                  subtitle: 'التحقق من توازن القيود وربط العمليات بدليل الحسابات',
                  onTap: () => Navigator.pushNamed(context, AppConstants.accountingAudit),
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.published_with_changes,
                  title: 'الترحيل السنوي',
                  subtitle: 'إقفال السنة المالية ونقل الأرباح إلى الأرباح المحتجزة',
                  onTap: () => Navigator.pushNamed(context, AppConstants.annualPosting),
                  isDark: isDark,
                ),
              ],
            ),

            // ── Data ───────────────────────────────────────────
            SettingsDataSection(
              isDark: isDark,
              saveSetting: _saveSetting,
              initialAutoBackupEnabled: _autoBackupEnabled,
              initialAutoBackupFrequencyIndex: _autoBackupFrequencyIndex,
              initialLastBackupDate: _lastBackupDate,
            ),

            // ── License ─────────────────────────────────────────
            _buildLicenseSection(isDark),

            // ── About ──────────────────────────────────────────
            SettingsGroup(
              title: 'حول التطبيق',
              icon: Icons.info,
              isDark: isDark,
              children: [
                ReadOnlySetting(
                  label: 'الإصدار',
                  value: AppConstants.appVersion,
                  icon: Icons.auto_awesome,
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.star,
                  title: 'تقييم التطبيق',
                  subtitle: 'شاركنا رأيك على المتجر',
                  onTap: _onRateApp,
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.email,
                  title: 'تواصل معنا',
                  subtitle: 'support@firstpro.com',
                  onTap: _onContactUs,
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.phone,
                  title: 'رقم الهاتف',
                  subtitle: '+967777777777',
                  onTap: _onCallUs,
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.chat,
                  title: 'واتساب',
                  subtitle: '+967777777777',
                  onTap: _onWhatsApp,
                  isDark: isDark,
                ),
                ActionTile(
                  icon: Icons.verified_user,
                  title: 'سياسة الخصوصية',
                  subtitle: 'عرض سياسة الخصوصية',
                  onTap: _onPrivacyPolicy,
                  isDark: isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  REMAINING INLINE BUILDERS (General section specifics)
  // ════════════════════════════════════════════════════════════════

  /// Currency link to currency management screen.
  Widget _buildCurrencyLink(bool isDark) {
    return ListTile(
      leading: Icon(Icons.attach_money, color: AppColors.primary, size: 22),
      title: const Text('إدارة العملات'),
      subtitle: const Text('العملات وأسعار الصرف'),
      trailing: Icon(
        Icons.arrow_back_ios,
        size: 16,
        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
      ),
      onTap: () => Navigator.pushNamed(context, AppConstants.currencies),
    );
  }

  /// Exchange rates management link.
  Widget _buildExchangeRatesLink(bool isDark) {
    return ListTile(
      leading: Icon(Icons.swap_horiz, color: AppColors.primary, size: 22),
      title: const Text('أسعار الصرف'),
      subtitle: const Text('تعديل أسعار الصرف للعملات'),
      trailing: Icon(
        Icons.arrow_back_ios,
        size: 16,
        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
      ),
      onTap: () => _showExchangeRatesDialog(),
    );
  }

  /// Show exchange rates management dialog.
  Future<void> _showExchangeRatesDialog() async {
    final currencies = await locator<ReferenceDataRepository>().getAllCurrencies();

    if (!mounted) return;

    final controllers = <String, TextEditingController>{};
    for (final c in currencies) {
      final code = c['code'] as String;
      controllers[code] = TextEditingController(
        text: (c['exchange_rate'] as num?)?.toDouble().toStringAsFixed(6) ?? '1.0',
      );
    }

    // Ensure controllers are disposed when the dialog closes, regardless of how
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أسعار الصرف'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: currencies.map((c) {
              final code = c['code'] as String;
              final symbol = c['symbol'] as String;
              final isDefault = (c['is_default'] as int?) == 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[code],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '$code ($symbol)',
                    prefixIcon: const Icon(Icons.monetization_on, size: 20),
                    suffixText: isDefault ? 'افتراضي' : '',
                    enabled: !isDefault,
                    helperText: isDefault ? 'العملة الافتراضية - سعر الصرف = 1' : 'سعر الصرف مقابل العملة الافتراضية',
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              for (final c in currencies) {
                final code = c['code'] as String;
                final rate = double.tryParse(controllers[code]?.text ?? '1.0') ?? 1.0;
                await locator<ReferenceDataRepository>().updateCurrency(c['id'] as int, {
                  'exchange_rate': rate,
                });
              }
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث أسعار الصرف بنجاح'), backgroundColor: AppColors.success),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ).whenComplete(() {
      // Always dispose controllers when the dialog closes, even if dismissed by tapping outside
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  }

  /// Tax rate slider.
  Widget _buildTaxSlider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('نسبة الضريبة'),
              Text(
                '${_taxRate.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _taxRate,
            min: 0,
            max: 25,
            divisions: 25,
            activeColor: AppColors.primary,
            label: '${_taxRate.toStringAsFixed(0)}%',
            onChanged: (v) {
              setState(() => _taxRate = v);
              _saveSetting('tax_rate', v.toStringAsFixed(1));
            },
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  THEME MODE SELECTOR
  // ════════════════════════════════════════════════════════════════
  Widget _buildThemeModeSelector(bool isDark) {
    const labels = ['فاتح', 'ليلي', 'تلقائي'];
    const icons = [Icons.light_mode, Icons.dark_mode, Icons.wb_twilight];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الوضع الليلي'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: List.generate(
              labels.length,
              (i) => ButtonSegment(
                value: i,
                label: Text(labels[i]),
                icon: Icon(icons[i], size: 18),
              ),
            ),
            selected: {_themeModeIndex},
            onSelectionChanged: (s) {
              setState(() => _themeModeIndex = s.first);
              _saveSetting('theme_mode_index', s.first.toString());
            },
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  FONT SIZE SELECTOR
  // ════════════════════════════════════════════════════════════════
  Widget _buildFontSizeSelector(bool isDark) {
    const labels = ['صغير', 'متوسط', 'كبير'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('حجم الخط'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: List.generate(
              labels.length,
              (i) => ButtonSegment(value: i, label: Text(labels[i])),
            ),
            selected: {_fontSizeIndex},
            onSelectionChanged: (s) {
              setState(() => _fontSizeIndex = s.first);
              _saveSetting('font_size_index', s.first.toString());
            },
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  LICENSE SECTION
  // ════════════════════════════════════════════════════════════════

  Widget _buildLicenseSection(bool isDark) {
    final licenseProvider = context.watch<LicenseProvider>();
    final licenseState = licenseProvider.state;

    // Build subtitle based on license status
    String subtitle;
    if (licenseState.status == LicenseStatus.active) {
      subtitle = 'نشط - ${licenseState.licenseType.arabicLabel}';
    } else if (licenseState.status == LicenseStatus.expired) {
      subtitle = 'منتهي الصلاحية';
    } else if (licenseState.status == LicenseStatus.revoked) {
      subtitle = 'ملغى';
    } else {
      subtitle = 'مجاني - ${LicenseConstants.freeRecordLimit} سجل';
    }

    return SettingsGroup(
      title: 'الترخيص',
      icon: Icons.vpn_key,
      isDark: isDark,
      children: [
        ActionTile(
          icon: Icons.verified,
          title: 'حالة الترخيص',
          subtitle: subtitle,
          onTap: () => Navigator.pushNamed(context, AppConstants.licenseStatus),
          isDark: isDark,
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  ABOUT ACTIONS
  // ════════════════════════════════════════════════════════════════

  void _onRateApp() {
    // Launch app store rating — uses in_app_review or store redirect
    try {
      // Android: open Play Store listing
      launchUrl(Uri.parse('market://details?id=com.nagmix.firstpro'));
    } catch (e) {
      // Fallback: open Play Store in browser
      launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=com.nagmix.firstpro'));
    }
  }

  void _onContactUs() {
    // Open email client to support@firstpro.com
    launchUrl(Uri.parse('mailto:support@firstpro.com?subject=دعم%20فني%20-%20الأول%20برو'));
  }

  void _onCallUs() {
    // Launch phone dialer
    launchUrl(Uri.parse('tel:+967777777777'));
  }

  void _onWhatsApp() {
    // Open WhatsApp chat with the support number
    launchUrl(Uri.parse('https://wa.me/967777777777?text=مرحباً،%20أحتاج%20مساعدة%20في%20تطبيق%20الأول%20برو'));
  }

  void _onPrivacyPolicy() {
    // Navigate to privacy policy page (or open in browser)
    launchUrl(Uri.parse('https://nagmix.net/privacy-policy'));
  }
}
