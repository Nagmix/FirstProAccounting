import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../navigation/app_router.dart';

/// Professional settings screen for the FirstPro accounting app.
///
/// Organized into logical groups:
/// 1. Profile section – business name, phone, email, logo (loaded from DB)
/// 2. عام (General) – business name, currency, tax rate, language
/// 3. الفواتير (Invoices) – auto-numbering, prefix, auto-print, show tax
/// 4. المخزون (Inventory) – stock alerts, threshold, expiry tracking
/// 5. العرض (Display) – theme mode, font size
/// 6. البيانات (Data) – backup, restore, export, clear data
/// 7. حول التطبيق (About) – version, rate, contact, privacy
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

  // ── General settings state ───────────────────────────────────────
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

  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = DatabaseHelper();
    final businessName = await db.getSetting('business_name');
    final phone = await db.getSetting('business_phone');
    final email = await db.getSetting('business_email');
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

    if (mounted) {
      setState(() {
        if (businessName != null) _businessNameController.text = businessName;
        if (phone != null) _phoneController.text = phone;
        if (email != null) _emailController.text = email;
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
        _isLoaded = true;
      });
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = DatabaseHelper();
    await db.setSetting(key, value);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _invoicePrefixController.dispose();
    super.dispose();
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
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile section ────────────────────────────────
            _buildProfileSection(theme, isDark),

            const SizedBox(height: 8),

            // ── General ────────────────────────────────────────
            _buildSettingsGroup(
              title: 'عام',
              icon: PhosphorIconsRegular.gear,
              isDark: isDark,
              children: [
                _buildTextSetting(
                  label: 'اسم النشاط التجاري',
                  controller: _businessNameController,
                  isDark: isDark,
                ),
                _buildCurrencyLink(isDark),
                _buildTaxSlider(isDark),
                _buildReadOnlySetting(
                  label: 'اللغة',
                  value: 'العربية',
                  icon: PhosphorIconsRegular.globe,
                  isDark: isDark,
                ),
              ],
            ),

            // ── Invoices ───────────────────────────────────────
            _buildSettingsGroup(
              title: 'الفواتير',
              icon: PhosphorIconsRegular.receipt,
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
              ],
            ),

            // ── Inventory ──────────────────────────────────────
            _buildSettingsGroup(
              title: 'المخزون',
              icon: PhosphorIconsRegular.package,
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
              ],
            ),

            // ── Display ────────────────────────────────────────
            _buildSettingsGroup(
              title: 'العرض',
              icon: PhosphorIconsRegular.paintBrush,
              isDark: isDark,
              children: [
                _buildThemeModeSelector(isDark),
                _buildFontSizeSelector(isDark),
              ],
            ),

            // ── Data ───────────────────────────────────────────
            _buildSettingsGroup(
              title: 'البيانات',
              icon: PhosphorIconsRegular.database,
              isDark: isDark,
              children: [
                _buildActionTile(
                  icon: PhosphorIconsRegular.cloudArrowUp,
                  title: 'نسخ احتياطي',
                  subtitle: 'حفظ نسخة من جميع البيانات',
                  onTap: _onBackup,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: PhosphorIconsRegular.cloudArrowDown,
                  title: 'استعادة البيانات',
                  subtitle: 'استعادة من نسخة احتياطية',
                  onTap: _onRestore,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: PhosphorIconsRegular.fileArrowDown,
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
              icon: PhosphorIconsRegular.info,
              isDark: isDark,
              children: [
                _buildReadOnlySetting(
                  label: 'الإصدار',
                  value: AppConstants.appVersion,
                  icon: PhosphorIconsRegular.shootingStar,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: PhosphorIconsRegular.star,
                  title: 'تقييم التطبيق',
                  subtitle: 'شاركنا رأيك على المتجر',
                  onTap: _onRateApp,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: PhosphorIconsRegular.envelope,
                  title: 'تواصل معنا',
                  subtitle: 'support@firstpro.sa',
                  onTap: _onContactUs,
                  isDark: isDark,
                ),
                _buildActionTile(
                  icon: PhosphorIconsRegular.shieldCheck,
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
          // ── Logo placeholder ─────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              PhosphorIconsRegular.buildings,
              size: 36,
              color: Colors.white,
            ),
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
            icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 18),
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
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
      leading: Icon(PhosphorIconsRegular.currencyDollar, color: AppColors.primary, size: 22),
      title: const Text('إدارة العملات'),
      subtitle: const Text('العملات وأسعار الصرف'),
      trailing: Icon(
        PhosphorIconsRegular.caretLeft,
        size: 16,
        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
      ),
      onTap: () => Navigator.pushNamed(context, AppRouter.currencies),
    );
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
                  icon: const Icon(PhosphorIconsRegular.minus, size: 20),
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
                  icon: const Icon(PhosphorIconsRegular.plus, size: 20),
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
        PhosphorIconsRegular.caretLeft,
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
      leading: const Icon(PhosphorIconsRegular.trash, color: AppColors.error, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.errorLight),
      ),
      trailing: const Icon(PhosphorIconsRegular.caretLeft, size: 16, color: AppColors.error),
      onTap: onTap,
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  THEME MODE SELECTOR
  // ════════════════════════════════════════════════════════════════
  Widget _buildThemeModeSelector(bool isDark) {
    const labels = ['فاتح', 'ليلي', 'تلقائي'];
    const icons = [PhosphorIconsRegular.sun, PhosphorIconsRegular.moon, PhosphorIconsRegular.sunHorizon];

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
  //  DIALOGS & ACTIONS
  // ════════════════════════════════════════════════════════════════

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات النشاط'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
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
              setState(() {});
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _onBackup() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جارٍ إنشاء النسخة الاحتياطية...'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _onRestore() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جارٍ استعادة البيانات...'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  void _onExportReports() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جارٍ تصدير التقارير...'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _onClearAllData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(PhosphorIconsRegular.warning, color: AppColors.error, size: 48),
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
    // TODO: Open email client
  }

  void _onPrivacyPolicy() {
    // TODO: Navigate to privacy policy page
  }
}
