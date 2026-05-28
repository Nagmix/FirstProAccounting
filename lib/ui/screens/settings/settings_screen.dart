import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../currency_exchange/currency_exchange_screen.dart';
import '../cash_transfers/cash_transfer_screen.dart';
import '../debts/debts_screen.dart';
import 'bluetooth_printer_settings_screen.dart';

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
  Timer? _autoBackupTimer;

  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings(); // _initAutoBackupTimer is called inside _loadSettings after state is ready
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _userNameController.dispose();
    _invoicePrefixController.dispose();
    _autoBackupTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Load per-installation salt for PIN hashing (C-04)
    _pinSalt = await _getOrCreatePinSalt();

    final db = DatabaseHelper();
    final businessName = await db.getSetting('business_name');
    final phone = await db.getSetting('business_phone');
    final email = await db.getSetting('business_email');
    final address = await db.getSetting('business_address');
    final logoPath = await db.getSetting('business_logo_path');
    final userName = await db.getSetting('user_name');
    final taxRate = await db.getSetting('tax_rate');
    final autoInvoice = await db.getSetting('auto_invoice_number');
    final invoicePrefix = await db.getSetting('invoice_prefix');
    final autoPrint = await db.getSetting('auto_print_after_sale');
    final showTax = await db.getSetting('show_tax_in_invoice');
    final stockAlert = await db.getSetting('stock_alert');
    final stockThreshold = await db.getSetting('stock_alert_threshold');
    final trackExpiry = await db.getSetting('track_expiry_date');
    final themeMode = await db.getSetting('theme_mode_index');
    final fontSize = await db.getSetting('font_size_index');
    // Read PIN enabled from secure storage with DB fallback for migration
    String? pinEnabled = await _secureStorage.read(key: 'pin_enabled');
    if (pinEnabled == null) {
      pinEnabled = await db.getSetting('pin_enabled');
      if (pinEnabled != null && pinEnabled.isNotEmpty) {
        // Migrate to secure storage
        await _secureStorage.write(key: 'pin_enabled', value: pinEnabled);
        await db.deleteSetting('pin_enabled');
      }
    }
    final biometricEnabled = await db.getSetting('biometric_enabled');
    final autoBackupEnabled = await db.getSetting('auto_backup_enabled');
    final autoBackupFreq = await db.getSetting('auto_backup_frequency');
    final lastBackup = await db.getSetting('last_backup_date');

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

    // Init auto-backup timer after settings are loaded
    _initAutoBackupTimer();
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = DatabaseHelper();
    await db.setSetting(key, value);
  }

  /// Secure SHA-256 based PIN hashing with per-installation salt (C-04).
  /// New format uses 'h3$' prefix; must match app_lock_screen.dart.
  String? _pinSalt;

  Future<String> _getOrCreatePinSalt() async {
    try {
      const storage = FlutterSecureStorage();
      var salt = await storage.read(key: 'pin_salt');
      if (salt == null || salt.isEmpty) {
        final random = DateTime.now().microsecondsSinceEpoch.toString() +
            DateTime.now().millisecond.toString();
        final saltBytes = sha256.convert(utf8.encode(random)).bytes;
        salt = base64Encode(saltBytes);
        await storage.write(key: 'pin_salt', value: salt);
      }
      return salt;
    } catch (_) {
      return 'F1r5tPr0_Fallback_2024_Salt';
    }
  }

  String _hashPin(String pin) {
    final salt = _pinSalt ?? 'F1r5tPr0_Fallback_2024_Salt';
    final key = utf8.encode('$salt$pin$salt');
    final bytes = sha256.convert(key).bytes;
    var currentBytes = bytes;
    for (var round = 0; round < 1000; round++) {
      final roundKey = utf8.encode('$salt${base64Encode(currentBytes)}$pin$round');
      currentBytes = sha256.convert(roundKey).bytes;
    }
    return 'h3\$${base64Encode(currentBytes)}';
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
            _buildProfileSection(theme, isDark),

            const SizedBox(height: 8),

            // ── General ────────────────────────────────────────
            _buildSettingsGroup(
              title: 'عام',
              icon: Icons.settings,
              isDark: isDark,
              children: [
                _buildTextSetting(
                  label: 'اسم المستخدم',
                  controller: _userNameController,
                  isDark: isDark,
                  onSave: () => _saveSetting('user_name', _userNameController.text),
                ),
                _buildTextSetting(
                  label: 'اسم النشاط التجاري',
                  controller: _businessNameController,
                  isDark: isDark,
                ),
                _buildCurrencyLink(isDark),
                _buildExchangeRatesLink(isDark),
                _buildTaxSlider(isDark),
                _buildReadOnlySetting(
                  label: 'اللغة',
                  value: 'العربية',
                  icon: Icons.language,
                  isDark: isDark,
                ),
              ],
            ),

            // ── Invoices ───────────────────────────────────────
            _buildSettingsGroup(
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
                _buildTextSetting(
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
                _buildActionTile(
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
            _buildSettingsGroup(
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
                _buildNumberSetting(
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
                _buildActionTile(
                  icon: Icons.inventory,
                  title: 'سندات الجرد',
                  subtitle: 'تسوية كميات المخزون وضبط القيود المحاسبية',
                  onTap: () => Navigator.pushNamed(context, AppConstants.inventoryVoucher),
                  isDark: isDark,
                ),
              ],
            ),

            // ── Display ────────────────────────────────────────
            _buildSettingsGroup(
              title: 'العرض',
              icon: Icons.brush,
              isDark: isDark,
              children: [
                _buildThemeModeSelector(isDark),
                _buildFontSizeSelector(isDark),
              ],
            ),

            // ── Operations (الأعمال) ────────────────────────────
            _buildSettingsGroup(
              title: 'الأعمال',
              icon: Icons.work,
              isDark: isDark,
              children: [
                _buildActionTile(
                  icon: Icons.swap_horiz,
                  title: 'مصارفة عملات',
                  subtitle: 'تحويل العملات بأسعار الصرف المحددة',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CurrencyExchangeScreen()),
                  ),
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.swap_horiz,
                  title: 'تحويل بين الصناديق',
                  subtitle: 'نقل الأموال بين الصناديق والخزائن',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CashTransferScreen()),
                  ),
                  isDark: isDark,
                ),
                _buildActionTile(
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
            _buildSettingsGroup(
              title: 'قفل التطبيق',
              icon: Icons.lock,
              isDark: isDark,
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.lock,
                    color: _pinEnabled ? AppColors.primary : null,
                  ),
                  title: const Text('تفعيل قفل PIN'),
                  subtitle: const Text('طلب رمز PIN عند فتح التطبيق'),
                  value: _pinEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (v) async {
                    if (v) {
                      // Enabling PIN — must set a PIN first
                      final pin = await _showPinDialog(isSetting: true);
                      if (pin != null && pin.length == 4) {
                        await _secureStorage.write(key: 'pin_enabled', value: '1');
                        await _secureStorage.write(key: 'app_pin', value: _hashPin(pin));
                        // Clean up old DB entries if they exist
                        try {
                          final db = DatabaseHelper();
                          await db.deleteSetting('pin_enabled');
                          await db.deleteSetting('app_pin');
                        } catch (_) {}
                        setState(() => _pinEnabled = true);
                      }
                    } else {
                      // Disabling PIN — delete from secure storage
                      await _secureStorage.delete(key: 'pin_enabled');
                      setState(() {
                        _pinEnabled = false;
                        _biometricEnabled = false;
                      });
                      await _saveSetting('biometric_enabled', '0');
                    }
                  },
                ),
                _buildActionTile(
                  icon: Icons.key,
                  title: _pinEnabled ? 'تغيير رمز PIN' : 'تعيين رمز PIN',
                  subtitle: _pinEnabled
                      ? 'تعديل رمز القفل المكون من 4 أرقام'
                      : 'تعيين رمز PIN من 4 أرقام لحماية التطبيق',
                  onTap: () async {
                    final pin = await _showPinDialog(isSetting: true);
                    if (pin != null && pin.length == 4) {
                      await _secureStorage.write(key: 'app_pin', value: _hashPin(pin));
                      // Clean up old DB entry if it exists
                      try {
                        await DatabaseHelper().deleteSetting('app_pin');
                      } catch (_) {}
                      if (!_pinEnabled) {
                        await _secureStorage.write(key: 'pin_enabled', value: '1');
                        try {
                          await DatabaseHelper().deleteSetting('pin_enabled');
                        } catch (_) {}
                        setState(() => _pinEnabled = true);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم حفظ رمز PIN بنجاح'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    }
                  },
                  isDark: isDark,
                ),
                SwitchListTile(
                  secondary: Icon(
                    Icons.fingerprint,
                    color: _biometricEnabled ? AppColors.primary : null,
                  ),
                  title: const Text('المصادقة البيومترية'),
                  subtitle: Text(
                    _isBiometricAvailable
                        ? 'استخدام البصمة أو الوجه للدخول'
                        : 'الجهاز لا يدعم المصادقة البيومترية',
                  ),
                  value: _biometricEnabled,
                  activeColor: AppColors.primary,
                  onChanged: _isBiometricAvailable && _pinEnabled
                      ? (v) async {
                          if (v) {
                            // Verify biometric before enabling
                            try {
                              final localAuth = LocalAuthentication();
                              final authenticated = await localAuth.authenticate(
                                localizedReason: 'قم بالمصادقة لتفعيل الدخول بالبصمة',
                                options: AuthenticationOptions(
                                  stickyAuth: true,
                                  biometricOnly: true,
                                ),
                              );
                              if (authenticated) {
                                await _saveSetting('biometric_enabled', '1');
                                setState(() => _biometricEnabled = true);
                              }
                            } on PlatformException {
                              // Biometric auth failed
                            }
                          } else {
                            await _saveSetting('biometric_enabled', '0');
                            setState(() => _biometricEnabled = false);
                          }
                        }
                      : null,
                ),
              ],
            ),

            // ── Accounting Audit ────────────────────────────────
            _buildSettingsGroup(
              title: 'المحاسبة',
              icon: Icons.verified_user,
              isDark: isDark,
              children: [
                _buildActionTile(
                  icon: Icons.search,
                  title: 'التدقيق المحاسبي',
                  subtitle: 'التحقق من توازن القيود وربط العمليات بدليل الحسابات',
                  onTap: () => Navigator.pushNamed(context, AppConstants.accountingAudit),
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.published_with_changes,
                  title: 'الترحيل السنوي',
                  subtitle: 'إقفال السنة المالية ونقل الأرباح إلى الأرباح المحتجزة',
                  onTap: () => Navigator.pushNamed(context, AppConstants.annualPosting),
                  isDark: isDark,
                ),
              ],
            ),

            // ── Data ───────────────────────────────────────────
            _buildSettingsGroup(
              title: 'البيانات',
              icon: Icons.storage,
              isDark: isDark,
              children: [
                _buildActionTile(
                  icon: Icons.cloud_upload,
                  title: 'نسخ احتياطي',
                  subtitle: 'حفظ نسخة من جميع البيانات',
                  onTap: _onBackup,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.cloud_download,
                  title: 'استعادة البيانات',
                  subtitle: 'استعادة من نسخة احتياطية',
                  onTap: _onRestore,
                  isDark: isDark,
                ),
                // ── Last backup info ─────────────────────────
                if (_lastBackupDate != null)
                  _buildReadOnlySetting(
                    label: 'آخر نسخة احتياطية',
                    value: _formatBackupDate(_lastBackupDate!),
                    icon: Icons.schedule,
                    isDark: isDark,
                  ),
                // ── Auto-backup toggle ───────────────────────
                SwitchListTile(
                  secondary: Icon(
                    Icons.backup_rounded,
                    color: _autoBackupEnabled ? AppColors.primary : null,
                  ),
                  title: const Text('نسخ احتياطي تلقائي'),
                  subtitle: Text(
                    _autoBackupEnabled
                        ? _autoBackupFrequencyIndex == 0
                            ? 'نسخ يومي تلقائي'
                            : 'نسخ أسبوعي تلقائي'
                        : 'إنشاء نسخ احتياطية تلقائياً',
                  ),
                  value: _autoBackupEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (v) async {
                    setState(() => _autoBackupEnabled = v);
                    await _saveSetting('auto_backup_enabled', v ? '1' : '0');
                    if (v) {
                      _initAutoBackupTimer();
                      await _performAutoBackup();
                    } else {
                      _autoBackupTimer?.cancel();
                    }
                  },
                ),
                // ── Auto-backup frequency ─────────────────────
                if (_autoBackupEnabled)
                  ListTile(
                    leading: Icon(Icons.timer, color: AppColors.primary, size: 22),
                    title: const Text('تكرار النسخ التلقائي'),
                    trailing: DropdownButton<int>(
                      value: _autoBackupFrequencyIndex,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('يومي')),
                        DropdownMenuItem(value: 1, child: Text('أسبوعي')),
                      ],
                      onChanged: (v) async {
                        if (v != null) {
                          setState(() => _autoBackupFrequencyIndex = v);
                          await _saveSetting(
                            'auto_backup_frequency',
                            v == 0 ? 'daily' : 'weekly',
                          );
                          _initAutoBackupTimer();
                        }
                      },
                    ),
                  ),
                _buildActionTile(
                  icon: Icons.file_download,
                  title: 'تصدير التقارير',
                  subtitle: 'تصدير التقارير كملف Excel',
                  onTap: _onExportReports,
                  isDark: isDark,
                ),
                _buildDangerTile(
                  title: 'مسح جميع البيانات',
                  subtitle: 'حذف جميع البيانات نهائياً',
                  onTap: _onClearAllData,
                ),
              ],
            ),

            // ── About ──────────────────────────────────────────
            _buildSettingsGroup(
              title: 'حول التطبيق',
              icon: Icons.info,
              isDark: isDark,
              children: [
                _buildReadOnlySetting(
                  label: 'الإصدار',
                  value: AppConstants.appVersion,
                  icon: Icons.auto_awesome,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.star,
                  title: 'تقييم التطبيق',
                  subtitle: 'شاركنا رأيك على المتجر',
                  onTap: _onRateApp,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.email,
                  title: 'تواصل معنا',
                  subtitle: 'support@firstpro.com',
                  onTap: _onContactUs,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.phone,
                  title: 'رقم الهاتف',
                  subtitle: '+967777777777',
                  onTap: _onCallUs,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: Icons.chat,
                  title: 'واتساب',
                  subtitle: '+967777777777',
                  onTap: _onWhatsApp,
                  isDark: isDark,
                ),
                _buildActionTile(
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
  //  PROFILE SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildProfileSection(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // ── Logo ─────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              image: _businessLogoPath != null
                  ? DecorationImage(image: FileImage(File(_businessLogoPath!)), fit: BoxFit.cover)
                  : null,
            ),
            child: _businessLogoPath == null
                ? const Icon(
                    Icons.business,
                    size: 36,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(height: 14),

          // ── Business name ────────────────────────────────────
          Text(
            _businessNameController.text.isEmpty
                ? 'اسم النشاط التجاري'
                : _businessNameController.text,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _phoneController.text.isEmpty && _emailController.text.isEmpty
                ? 'أضف بيانات النشاط'
                : '${_phoneController.text.isEmpty ? '—' : _phoneController.text}  •  ${_emailController.text.isEmpty ? '—' : _emailController.text}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),

          // ── Edit profile button ──────────────────────────────
          OutlinedButton.icon(
            onPressed: _showEditProfileDialog,
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('تعديل البيانات'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SETTINGS GROUP WRAPPER
  // ════════════════════════════════════════════════════════════════
  Widget _buildSettingsGroup({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  INDIVIDUAL SETTING BUILDERS
  // ════════════════════════════════════════════════════════════════

  /// Text field setting with a label and controller.
  Widget _buildTextSetting({
    required String label,
    required TextEditingController controller,
    required bool isDark,
    VoidCallback? onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        onSubmitted: (_) => onSave?.call(),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }

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
    final db = DatabaseHelper();
    final currencies = await db.getAllCurrencies();

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
                await db.updateCurrency(c['id'] as int, {
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

  /// Read-only setting displayed as a simple ListTile.
  Widget _buildReadOnlySetting({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// Number input setting with increment/decrement buttons.
  Widget _buildNumberSetting({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: value > 1 ? () => onChanged(value - 1) : null,
                  icon: const Icon(Icons.remove, size: 20),
                  splashRadius: 18,
                ),
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: value < 999 ? () => onChanged(value + 1) : null,
                  icon: const Icon(Icons.add, size: 20),
                  splashRadius: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Action tile (tappable ListTile).
  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
        ),
      ),
      trailing: Icon(
        Icons.arrow_back_ios,
        size: 16,
        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
      ),
      onTap: onTap,
    );
  }

  /// Danger action tile (red accent).
  Widget _buildDangerTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: const Icon(Icons.delete, color: AppColors.error, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.errorLight),
      ),
      trailing: const Icon(Icons.arrow_back_ios, size: 16, color: AppColors.error),
      onTap: onTap,
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
  //  PIN DIALOG
  // ════════════════════════════════════════════════════════════════

  /// Shows a dialog for entering a 4-digit PIN.
  /// Returns the entered PIN string if confirmed, or null if cancelled.
  Future<String?> _showPinDialog({required bool isSetting}) async {
    String pin = '';
    String confirmPin = '';
    bool isConfirming = false;
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void onDigit(String digit) {
              if (isConfirming && confirmPin.length >= 4) return;
              if (!isConfirming && pin.length >= 4) return;

              setDialogState(() {
                if (isConfirming) {
                  confirmPin += digit;
                } else {
                  pin += digit;
                }
                errorText = null;
              });

              // Auto-advance to confirm step
              if (!isConfirming && pin.length == 4) {
                setDialogState(() {
                  isConfirming = true;
                });
              }

              // Auto-confirm when confirmation PIN is complete
              if (isConfirming && confirmPin.length == 4) {
                if (pin == confirmPin) {
                  Navigator.pop(ctx, pin);
                } else {
                  setDialogState(() {
                    errorText = 'رمز PIN غير متطابق، حاول مرة أخرى';
                    confirmPin = '';
                    isConfirming = true;
                    pin = '';
                    isConfirming = false;
                  });
                }
              }
            }

            void onBackspace() {
              setDialogState(() {
                if (isConfirming && confirmPin.isNotEmpty) {
                  confirmPin = confirmPin.substring(0, confirmPin.length - 1);
                } else if (!isConfirming && pin.isNotEmpty) {
                  pin = pin.substring(0, pin.length - 1);
                }
                errorText = null;
              });
            }

            final currentPin = isConfirming ? confirmPin : pin;
            final title = isConfirming ? 'أعد إدخال رمز PIN' : 'أدخل رمز PIN الجديد';

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PIN dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < currentPin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: errorText != null
                                ? AppColors.error
                                : isFilled
                                    ? AppColors.primary
                                    : Colors.grey[400]!,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  const SizedBox(height: 12),
                  // Numeric keypad
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var d = 1; d <= 9; d++)
                        SizedBox(
                          width: 64,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => onDigit(d.toString()),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              d.toString(),
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 64,
                        height: 48,
                        child: IconButton(
                          onPressed: onBackspace,
                          icon: const Icon(Icons.backspace),
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => onDigit('0'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('0', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      SizedBox(width: 64, height: 48), // spacer
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  DIALOGS & ACTIONS
  // ════════════════════════════════════════════════════════════════

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات النشاط'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo picker ──
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
                  if (picked != null) {
                    // Save to app documents directory
                    final dir = await getApplicationDocumentsDirectory();
                    final logoDir = p.join(dir.path, 'business_logo${p.extension(picked.path)}');
                    await File(picked.path).copy(logoDir);
                    setState(() => _businessLogoPath = logoDir);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showEditProfileDialog(); // Reopen to reflect new logo
                  }
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: _businessLogoPath != null ? FileImage(File(_businessLogoPath!)) : null,
                  child: _businessLogoPath == null
                      ? const Icon(Icons.add_a_photo, size: 32, color: AppColors.primary)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text('اضغط لتغيير الشعار', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              if (_businessLogoPath != null)
                TextButton(
                  onPressed: () async {
                    setState(() => _businessLogoPath = null);
                    await _saveSetting('business_logo_path', '');
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showEditProfileDialog();
                  },
                  child: const Text('إزالة الشعار', style: TextStyle(fontSize: 11, color: AppColors.error)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _businessNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم النشاط التجاري',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await _saveSetting('business_name', _businessNameController.text);
              await _saveSetting('business_phone', _phoneController.text);
              await _saveSetting('business_email', _emailController.text);
              await _saveSetting('business_address', _addressController.text);
              if (_businessLogoPath != null) {
                await _saveSetting('business_logo_path', _businessLogoPath!);
              }
              setState(() {});
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _onBackup() async {
    try {
      final dbHelper = DatabaseHelper();
      final dbPath = await dbHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لم يتم العثور على قاعدة البيانات')),
          );
        }
        return;
      }

      // Save auto-backup copy
      await _saveAutoBackup(dbFile);

      // Create timestamped backup for sharing
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final backupPath = p.join(dir.path, 'firstpro_backup_$timestamp.db');
      await dbFile.copy(backupPath);

      // Update last backup date
      final now = DateTime.now().toIso8601String();
      await _saveSetting('last_backup_date', now);
      setState(() => _lastBackupDate = now);

      // Share the backup file
      await Share.shareXFiles(
        [XFile(backupPath)],
        text: 'نسخة احتياطية - الأول برو المحاسبي',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء النسخة الاحتياطية بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في النسخ الاحتياطي: $e')),
        );
      }
    }
  }

  /// Save a backup copy to the auto-backup directory and clean up old ones.
  Future<void> _saveAutoBackup(File dbFile) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, 'auto_backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final autoBackupPath = p.join(backupDir.path, 'auto_backup_$timestamp.db');
      await dbFile.copy(autoBackupPath);

      // Clean up old backups – keep only the last 5
      final backupFiles = await backupDir
          .list()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      if (backupFiles.length > 5) {
        // Sort by modification time, oldest first
        backupFiles.sort((a, b) =>
            FileStat.statSync(a.path).modified.compareTo(FileStat.statSync(b.path).modified));
        for (var i = 0; i < backupFiles.length - 5; i++) {
          await backupFiles[i].delete();
        }
      }
    } catch (_) {
      // Auto-backup save failure should not block the main backup flow
    }
  }

  /// Perform auto-backup silently (no share dialog).
  Future<void> _performAutoBackup() async {
    try {
      final dbHelper = DatabaseHelper();
      final dbPath = await dbHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      await _saveAutoBackup(dbFile);

      // Update last backup date
      final now = DateTime.now().toIso8601String();
      await _saveSetting('last_backup_date', now);
      if (mounted) {
        setState(() => _lastBackupDate = now);
      }
    } catch (_) {
      // Silent failure for auto-backup
    }
  }

  /// Initialize or reinitialize the periodic auto-backup timer.
  void _initAutoBackupTimer() {
    _autoBackupTimer?.cancel();
    if (!_autoBackupEnabled) return;

    // Check if a backup is needed on startup
    _checkAndPerformAutoBackup();

    // Periodic check: every 1 hour for daily, every 6 hours for weekly
    final interval = _autoBackupFrequencyIndex == 0
        ? const Duration(hours: 1)
        : const Duration(hours: 6);

    _autoBackupTimer = Timer.periodic(interval, (_) {
      _checkAndPerformAutoBackup();
    });
  }

  /// Check if enough time has passed since the last backup, then perform one.
  Future<void> _checkAndPerformAutoBackup() async {
    if (!_autoBackupEnabled) return;

    final db = DatabaseHelper();
    final lastBackupStr = await db.getSetting('last_backup_date');
    if (lastBackupStr != null) {
      final lastBackup = DateTime.tryParse(lastBackupStr);
      if (lastBackup != null) {
        final now = DateTime.now();
        final difference = now.difference(lastBackup);
        final threshold = _autoBackupFrequencyIndex == 0
            ? const Duration(hours: 24) // daily
            : const Duration(days: 7); // weekly
        if (difference < threshold) return; // Not yet time
      }
    }

    await _performAutoBackup();
  }

  /// Format a backup date string for display.
  String _formatBackupDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _onRestore() async {
    // Show restore source options
    final source = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة البيانات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open, color: AppColors.primary),
              title: const Text('اختيار ملف من الجهاز'),
              subtitle: const Text('اختر ملف .db من تخزين الجهاز'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.primary),
              title: const Text('النسخ الاحتياطية التلقائية'),
              subtitle: const Text('استعادة من نسخة محفوظة تلقائياً'),
              onTap: () => Navigator.pop(ctx, 'auto'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (source == null || !mounted) return;

    String? backupFilePath;

    if (source == 'file') {
      // Use file_picker to select a .db file
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['db'],
          dialogTitle: 'اختر ملف النسخة الاحتياطية',
        );
        if (result != null && result.files.single.path != null) {
          backupFilePath = result.files.single.path!;
        } else {
          return; // User cancelled
        }
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في فتح ملف: $e')),
          );
        }
        return;
      }
    } else if (source == 'auto') {
      // List available auto-backup files
      final autoFile = await _pickAutoBackupFile();
      if (autoFile == null) return;
      backupFilePath = autoFile;
    }

    if (backupFilePath == null || !mounted) return;

    // Show warning dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 48),
        title: const Text('تحذير: استعادة البيانات'),
        content: const Text(
          'تحذير: ستتم استبدال جميع البيانات الحالية بالنسخة الاحتياطية. هل أنت متأكد؟\n\n'
 'لا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warning,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Perform the restore
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('جارٍ استعادة البيانات...'),
            ],
          ),
        ),
      );

      final dbHelper = DatabaseHelper();

      // 1. Close the database connection
      await dbHelper.resetInstance();

      // 2. Replace the current DB file with the backup
      final dbPath = await dbHelper.getDatabasePath();
      final backupFile = File(backupFilePath!);
      await backupFile.copy(dbPath);

      // 3. Reopen the database (will happen automatically on next access)
      // Trigger it by accessing the database
      await dbHelper.database;

      // 4. Update last backup date
      final now = DateTime.now().toIso8601String();
      await _saveSetting('last_backup_date', now);

      // 5. Dismiss loading
      if (mounted) {
        Navigator.pop(context); // dismiss loading dialog
      }

      // 6. Show success and prompt restart
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            title: const Text('تمت الاستعادة بنجاح'),
            content: const Text(
              'تم استعادة البيانات من النسخة الاحتياطية بنجاح.\n'
              'يُنصح بإعادة تشغيل التطبيق لضمان تحميل جميع البيانات.',
              textAlign: TextAlign.center,
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Reload settings to reflect restored data
                  _loadSettings();
                },
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Dismiss loading if still visible
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في استعادة البيانات: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// List available auto-backup files and let user pick one.
  Future<String?> _pickAutoBackupFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, 'auto_backups'));

      if (!await backupDir.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد نسخ احتياطية تلقائية محفوظة')),
          );
        }
        return null;
      }

      final files = await backupDir
          .list()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد نسخ احتياطية تلقائية محفوظة')),
          );
        }
        return null;
      }

      // Sort by modification time, newest first
      files.sort((a, b) =>
          FileStat.statSync(b.path).modified.compareTo(FileStat.statSync(a.path).modified));

      if (!mounted) return null;

      // Show picker dialog
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اختر نسخة احتياطية'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (_, index) {
                final file = files[index];
                final stat = FileStat.statSync(file.path);
                final modified = stat.modified;
                final sizeKB = (stat.size / 1024).toStringAsFixed(1);
                final dateStr = '${modified.year}/${modified.month.toString().padLeft(2, '0')}/${modified.day.toString().padLeft(2, '0')} '
                    '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: AppColors.primary),
                  title: Text(dateStr),
                  subtitle: Text('الحجم: ${sizeKB} ك.ب'),
                  onTap: () => Navigator.pop(ctx, file.path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في قراءة النسخ الاحتياطية: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _onExportReports() async {
    // عرض خيارات التصدير
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصدير التقارير'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_tree, color: AppColors.primary),
              title: const Text('تصدير الحسابات'),
              subtitle: const Text('شجرة الحسابات'),
              onTap: () => Navigator.pop(ctx, 'accounts'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt, color: AppColors.primary),
              title: const Text('تصدير الفواتير'),
              subtitle: const Text('قائمة الفواتير'),
              onTap: () => Navigator.pop(ctx, 'invoices'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2, color: AppColors.primary),
              title: const Text('تصدير المخزون'),
              subtitle: const Text('بيانات المنتجات والمخزون'),
              onTap: () => Navigator.pop(ctx, 'inventory'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: AppColors.primary),
              title: const Text('تصدير الحركات'),
              subtitle: const Text('القيود المحاسبية'),
              onTap: () => Navigator.pop(ctx, 'transactions'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    try {
      final db = DatabaseHelper();
      String filePath;

      switch (choice) {
        case 'accounts':
          final accounts = await db.getAllAccounts();
          filePath = await ExcelExporter.exportAccountsToExcel(accounts);
          break;
        case 'invoices':
          final invoices = await db.getAllInvoices();
          filePath = await ExcelExporter.exportInvoicesToExcel(invoices);
          break;
        case 'inventory':
          final products = await db.getAllProducts();
          filePath = await ExcelExporter.exportInventoryToExcel(products);
          break;
        case 'transactions':
          final transactions = await db.getAllTransactionsForExport();
          filePath = await ExcelExporter.exportTransactionsToExcel(transactions);
          break;
        default:
          return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير التقرير بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير التقرير: $e')),
        );
      }
    }
  }

  void _onClearAllData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 48),
        title: const Text('مسح جميع البيانات'),
        content: const Text(
          'هل أنت متأكد من حذف جميع البيانات؟ لا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم مسح جميع البيانات'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            child: const Text('مسح'),
          ),
        ],
      ),
    );
  }

  void _onRateApp() {
    // TODO: Launch app store rating
  }

  void _onContactUs() {
    // TODO: Open email client to support@firstpro.com
  }

  void _onCallUs() {
    // TODO: Launch phone dialer with +967777777777
  }

  void _onWhatsApp() {
    // TODO: Open WhatsApp with +967777777777
  }

  void _onPrivacyPolicy() {
    // TODO: Navigate to privacy policy page
  }
}
