import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../settings/bluetooth_printer_settings_screen.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/invoice_model.dart';
import '../../widgets/invoice_item_card.dart';
import '../customers/add_customer_sheet.dart';
import '../suppliers/add_supplier_sheet.dart';
import 'add_invoice_item_sheet.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key, required this.invoiceType, this.existingInvoice});

  final String invoiceType;
  final Invoice? existingInvoice;

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _discountController = TextEditingController();
  final _paidController = TextEditingController();
  final _transportChargesController = TextEditingController();
  final _transferNumberController = TextEditingController();
  final _entitySearchController = TextEditingController();

  // Payment mechanism: cash or credit
  String _paymentMechanism = 'cash';
  // Payment method: cash, check, transfer, bank, ewallet, bank_transfer
  String _paymentMethod = 'cash';
  // Is return invoice
  bool _isReturn = false;
  // Auto-pay checkbox
  bool _autoPay = true;

  // Entity selection — unified: customers + suppliers
  int? _selectedEntityId;
  String? _selectedEntityType; // 'customer' or 'supplier'
  int? _selectedWarehouseId;
  int? _selectedCashBoxId;
  final List<InvoiceItem> _items = [];

  // E-wallet state
  String? _selectedEwalletProvider;
  // Bank transfer state
  String? _selectedBankTransferProvider;
  // Attachment image
  String? _attachmentPath;

  // Original invoice for returns
  String? _originalInvoiceId;
  String? _originalInvoiceDisplay;

  // Data from DB
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _combinedEntities = [];
  List<Map<String, dynamic>> _filteredEntities = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  List<Map<String, dynamic>> _currencies = [];
  String _selectedCurrency = 'YER';
  double _selectedExchangeRate = 1.0;
  bool _isLoading = true;
  bool _showEntityDropdown = false;

  // E-wallet providers list
  static const List<String> _ewalletProviders = [
    'جيب', 'فلوسك', 'كاش', 'ون كاش', 'جوالي', 'الكريمي',
    'موبايل موني', 'محفظتي', 'شامل موني', 'سبأ كاش', 'ايزي', 'يمن والت', 'أخرى',
  ];

  // Bank transfer providers list
  static const List<String> _bankTransferProviders = [
    'الامتياز', 'النجم', 'يمن اكسبرس', 'الحزمي اكسبرس', 'الاكوع كوني',
    'السريع للحوالات', 'ياه موني', 'عامري كاش', 'الناصر اكسبرس',
    'المحيط اكسبرس', 'تحويل', 'أخرى',
  ];

  bool get _isSale => widget.invoiceType == 'sale';

  String get _title {
    String base = _isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات';
    if (_isReturn) base = 'فاتورة مرتجع $base';
    return '$base جديدة';
  }

  // Entity is required when: credit mechanism OR (paid < total)
  bool get _isEntityRequired =>
      _paymentMechanism == 'credit' || _remaining > 0.005;

  @override
  void initState() {
    super.initState();
    _loadData();
    _paidController.text = '0.00';
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAllCustomers(),
      db.getAllSuppliers(),
      db.getAllWarehouses(),
      db.getAllCashBoxes(),
      db.getAllCurrencies(),
    ]);
    setState(() {
      _customers = results[0];
      _suppliers = results[1];
      _warehouses = results[2];
      _cashBoxes = results[3];
      _currencies = results[4];
      _buildCombinedEntities();
      _isLoading = false;
    });
  }

  void _buildCombinedEntities() {
    _combinedEntities = [];
    for (final c in _customers) {
      _combinedEntities.add({
        'id': c['id'],
        'name': c['name'],
        'type': 'customer',
        'balance': (c['balance'] as num?)?.toDouble() ?? 0.0,
        'balance_type': c['balance_type'] ?? 'credit',
      });
    }
    for (final s in _suppliers) {
      _combinedEntities.add({
        'id': s['id'],
        'name': s['name'],
        'type': 'supplier',
        'balance': (s['balance'] as num?)?.toDouble() ?? 0.0,
        'balance_type': s['balance_type'] ?? 'credit',
      });
    }
    _filteredEntities = List.from(_combinedEntities);
  }

  void _filterEntities(String query) {
    if (query.isEmpty) {
      _filteredEntities = List.from(_combinedEntities);
    } else {
      final q = query.toLowerCase();
      _filteredEntities = _combinedEntities.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        return name.contains(q);
      }).toList();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _transportChargesController.dispose();
    _transferNumberController.dispose();
    _entitySearchController.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  double get _discountAmount => double.tryParse(_discountController.text) ?? 0;
  double get _transportCharges => double.tryParse(_transportChargesController.text) ?? 0;
  double get _taxAmount => (_subtotal - _discountAmount) * (AppConstants.defaultVatRate / 100);
  double get _total => _subtotal - _discountAmount + _taxAmount + _transportCharges;
  double get _paidAmount => double.tryParse(_paidController.text) ?? 0;
  double get _remaining => _total - _paidAmount;
  // YER-equivalent getters for multi-currency display
  double get _totalInBaseCurrency => _total * _selectedExchangeRate;
  double get _paidAmountInBaseCurrency => _paidAmount * _selectedExchangeRate;
  double get _remainingInBaseCurrency => _remaining * _selectedExchangeRate;

  void _updateAutoPay() {
    if (_autoPay && _total > 0) {
      _paidController.text = _total.toStringAsFixed(2);
    }
  }

  String? get _selectedEntityName {
    if (_selectedEntityId == null) return null;
    final entity = _combinedEntities.where((e) => e['id'] == _selectedEntityId && e['type'] == _selectedEntityType).firstOrNull;
    return entity?['name'] as String?;
  }

  // ── Image picker helpers ─────────────────────────────────────
  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final savedPath = await _saveImageLocally(picked);
      if (savedPath != null) {
        setState(() => _attachmentPath = savedPath);
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) {
      final savedPath = await _saveImageLocally(picked);
      if (savedPath != null) {
        setState(() => _attachmentPath = savedPath);
      }
    }
  }

  Future<String?> _saveImageLocally(XFile image) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory('${dir.path}/attachments');
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }
      final fileName = 'inv_${DateTime.now().millisecondsSinceEpoch}${p.extension(image.path)}';
      final newPath = '${attachmentsDir.path}/$fileName';
      await File(image.path).copy(newPath);
      return newPath;
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('فشل حفظ الصورة');
      }
      return null;
    }
  }

  // ── Design helpers ──────────────────────────────────────────────
  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

  LinearGradient get _primaryGradient => const LinearGradient(
    colors: [_accentBlue, _accentPurple],
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
  );

  Widget _sectionHeader(String title, {IconData icon = Icons.label_important_rounded, Widget? trailing}) {
    final isDark = context.isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: _primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 20, color: _accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.3,
                color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FE),
        appBar: _buildAppBar(isDark),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: _accentBlue))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Partial payment warning
                      if (!_autoPay && _paymentMechanism == 'cash' && _paidAmount > 0 && _remaining > 0.005)
                        _buildPartialPaymentWarning(),
                      // Payment Section
                      _buildPaymentSection(isDark),
                      const SizedBox(height: 16),
                      // Entity Section
                      _buildEntitySection(isDark),
                      const SizedBox(height: 16),
                      // Items section
                      _buildItemsSection(isDark),
                      const SizedBox(height: 16),
                      // Summary & Notes
                      _buildSummarySection(isDark),
                      const SizedBox(height: 90), // Bottom padding for scroll
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Modern AppBar ────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      elevation: 0,
      toolbarHeight: 64,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: _primaryGradient,
          boxShadow: [
            BoxShadow(
              color: _accentBlue.withOpacity(0.25),
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
          ],
        ),
      ),
      leading: Container(
        margin: const EdgeInsets.only(right: 4),
        child: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isSale ? Icons.receipt_long_rounded : Icons.shopping_cart_rounded,
              color: Colors.white, size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(_title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isReturn) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('مرتجع',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.more_horiz, size: 20, color: Colors.white),
          ),
          tooltip: 'إجراءات',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark ? AppColors.darkSurface : Colors.white,
          onSelected: (value) {
            switch (value) {
              case 'print':
                _printInvoice();
                break;
              case 'bluetooth':
                _printBluetooth();
                break;
              case 'share':
                _shareInvoice();
                break;
              case 'whatsapp':
                _shareInvoiceWhatsApp();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'print', child: _popupItem(Icons.print_rounded, 'طباعة PDF', const Color(0xFF4F6AF0))),
            PopupMenuItem(value: 'bluetooth', child: _popupItem(Icons.bluetooth_rounded, 'طباعة حرارية', const Color(0xFF3B82F6))),
            PopupMenuItem(value: 'share', child: _popupItem(Icons.share_rounded, 'مشاركة', const Color(0xFFF97316))),
            PopupMenuItem(value: 'whatsapp', child: _popupItem(Icons.chat_rounded, 'واتساب', const Color(0xFF25D366))),
          ],
        ),
        const SizedBox(width: 4),
        Container(
          margin: const EdgeInsets.only(left: 8, top: 12, bottom: 12, right: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.1)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _saveInvoice,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _popupItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  // ── Partial payment warning ──────────────────────────────────────
  Widget _buildPartialPaymentWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'المبلغ المدفوع أقل من المستحق. المتبقي سيتم تسجيله كرصد آجل',
              style: context.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment Section (Currency + Return + Payment Mechanism) ──────
  Widget _buildPaymentSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('تفاصيل الدفع', icon: Icons.payment_rounded),
          // Currency + Return in one row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildModernDropdown<String>(
                  value: _selectedCurrency,
                  label: 'العملة',
                  icon: Icons.monetization_on_rounded,
                  items: _currencies.map((c) => DropdownMenuItem<String>(
                    value: c['code'] as String,
                    child: Text('${c['code']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  )).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedCurrency = val;
                      final currency = _currencies.where((c) => c['code'] == val).firstOrNull;
                      if (currency != null) {
                        _selectedExchangeRate = (currency['exchange_rate'] as num?)?.toDouble() ?? 1.0;
                      }
                    });
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildReturnToggle(isDark),
              ),
            ],
          ),
          // Original invoice selector (only when _isReturn is true)
          if (_isReturn) ...[
            const SizedBox(height: 12),
            _buildOriginalInvoiceSelector(isDark),
          ],
          if (_selectedCurrency != 'YER')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentBlue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_vert_rounded, size: 14, color: _accentBlue),
                    const SizedBox(width: 4),
                    Text(
                      'سعر الصرف: $_selectedExchangeRate',
                      style: context.textTheme.bodySmall?.copyWith(color: _accentBlue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Payment mechanism segmented control
          _buildPaymentMechanismControl(isDark),
          // Credit info
          if (_paymentMechanism == 'credit') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentOrange.withOpacity(0.08), AppColors.accentOrange.withOpacity(0.03)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accentOrange.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.info_outline_rounded, color: AppColors.accentOrange, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم تسجيل المبلغ كرصيد على الحساب',
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Payment method pills (only when cash)
          if (_paymentMechanism == 'cash') ...[
            const SizedBox(height: 14),
            _buildPaymentMethodRow(isDark),
          ],
          // E-wallet / bank transfer sections
          if (_paymentMechanism == 'cash' && _paymentMethod == 'ewallet')
            _buildEwalletSection(isDark),
          if (_paymentMechanism == 'cash' && _paymentMethod == 'bank_transfer')
            _buildBankTransferSection(isDark),
          // Cash box + paid amount
          if (_paymentMechanism == 'cash') ...[
            const SizedBox(height: 14),
            _buildCashBoxAndPaidRow(isDark),
          ],
        ],
      ),
    );
  }

  // ── Modern dropdown helper ────────────────────────────────────────
  Widget _buildModernDropdown<T>({
    required T? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? Function(T?)? validator,
    bool isDark = false,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Container(
          margin: const EdgeInsets.only(left: 8),
          child: Icon(icon, size: 20, color: _accentBlue),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }

  // ── Return toggle ─────────────────────────────────────────────────
  Widget _buildReturnToggle(bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _isReturn = !_isReturn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: _isReturn
              ? AppColors.error.withOpacity(isDark ? 0.12 : 0.06)
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isReturn ? AppColors.error : (isDark ? AppColors.darkBorder : AppColors.border),
            width: _isReturn ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _isReturn ? Icons.undo_rounded : Icons.undo_outlined,
                key: ValueKey(_isReturn),
                size: 16,
                color: _isReturn ? AppColors.error : AppColors.textHint,
              ),
            ),
            const SizedBox(width: 6),
            Text('مرتجع', style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _isReturn ? AppColors.error : AppColors.textHint,
            )),
          ],
        ),
      ),
    );
  }

  // ── Payment mechanism segmented control ──────────────────────────
  Widget _buildPaymentMechanismControl(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildMechanismSegment(
              icon: Icons.payments_rounded,
              label: 'نقداً',
              isSelected: _paymentMechanism == 'cash',
              color: AppColors.success,
              onTap: () => setState(() => _paymentMechanism = 'cash'),
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildMechanismSegment(
              icon: Icons.schedule_rounded,
              label: 'أجل',
              isSelected: _paymentMechanism == 'credit',
              color: AppColors.accentOrange,
              onTap: () => setState(() {
                _paymentMechanism = 'credit';
                _selectedCashBoxId = null;
                _autoPay = false;
                _paidController.text = '0';
              }),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMechanismSegment({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: isSelected
              ? Border.all(color: color.withOpacity(0.3), width: 1)
              : null,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(icon,
                key: ValueKey(isSelected),
                size: 18,
                color: isSelected ? color : AppColors.textHint,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? color : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, size: 14, color: color),
            ],
          ],
        ),
      ),
    );
  }

  // ── Original Invoice Selector (for returns) ────────────────────────
  Widget _buildOriginalInvoiceSelector(bool isDark) {
    return GestureDetector(
      onTap: _showOriginalInvoiceSelector,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _originalInvoiceId != null
              ? AppColors.error.withOpacity(isDark ? 0.08 : 0.04)
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _originalInvoiceId != null
                ? AppColors.error.withOpacity(0.4)
                : (isDark ? AppColors.darkBorder : AppColors.border),
            width: _originalInvoiceId != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: (_originalInvoiceId != null ? AppColors.error : AppColors.textHint).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.link_rounded,
                size: 14,
                color: _originalInvoiceId != null ? AppColors.error : AppColors.textHint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _originalInvoiceDisplay ?? 'اختر الفاتورة الأصلية...',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: _originalInvoiceId != null ? AppColors.textPrimary : AppColors.textHint,
                  fontWeight: _originalInvoiceId != null ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (_originalInvoiceId != null)
              GestureDetector(
                onTap: () => setState(() {
                  _originalInvoiceId = null;
                  _originalInvoiceDisplay = null;
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close_rounded, size: 14, color: AppColors.error),
                ),
              )
            else
              Icon(Icons.arrow_drop_down_rounded, size: 22, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  void _showOriginalInvoiceSelector() async {
    final db = DatabaseHelper();
    // Get recent non-return invoices of the same type (sale or purchase)
    final invoices = await db.getInvoicesByType(widget.invoiceType);

    // Filter to only non-return invoices
    final nonReturnInvoices = invoices.where((inv) {
      final isReturn = (inv['is_return'] as int?) == 1;
      final status = inv['status'] as String? ?? '';
      return !isReturn && status != 'cancelled';
    }).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: _accentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded, color: _accentBlue, size: 18),
              ),
              const SizedBox(width: 10),
              Text('اختر الفاتورة الأصلية', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: nonReturnInvoices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: _accentBlue.withOpacity(0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.receipt_long_rounded, size: 28, color: _accentBlue.withOpacity(0.4)),
                        ),
                        const SizedBox(height: 12),
                        Text('لا توجد فواتير أصلية', style: context.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: nonReturnInvoices.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, index) {
                      final inv = nonReturnInvoices[index];
                      final invId = inv['id'] as String? ?? '';
                      final entityName = inv['entity_name'] as String? ?? '—';
                      final total = (inv['total'] as num?)?.toDouble() ?? 0.0;
                      final createdAt = DateTime.tryParse(inv['created_at'] as String? ?? '');
                      final dateStr = createdAt != null ? DateFormatter.formatDateTime(createdAt) : '';
                      final displayId = invId.length > 12 ? '...${invId.substring(invId.length - 8)}' : invId;
                      final isSelected = _originalInvoiceId != null && invId == _originalInvoiceId;

                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        selected: isSelected,
                        selectedTileColor: _accentBlue.withOpacity(0.06),
                        leading: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: (isSelected ? _accentBlue : AppColors.textSecondary).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _isSale ? Icons.receipt_rounded : Icons.shopping_cart_rounded,
                            color: isSelected ? _accentBlue : AppColors.textSecondary,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          '# $displayId',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? _accentBlue : null,
                          ),
                        ),
                        subtitle: Text(
                          '$entityName • ${CurrencyFormatter.format(total)} • $dateStr',
                          style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                        trailing: isSelected
                            ? Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _accentBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.check_rounded, color: _accentBlue, size: 16),
                              )
                            : null,
                        onTap: () {
                          setState(() {
                            _originalInvoiceId = invId;
                            _originalInvoiceDisplay = '# $displayId • $entityName • ${CurrencyFormatter.format(total)}';
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Payment method pills ──────────────────────────────────────────
  Widget _buildPaymentMethodRow(bool isDark) {
    const methods = [
      ('cash', 'نقدي', Icons.payments_rounded, AppColors.success),
      ('check', 'شيك', Icons.sticky_note_2_rounded, AppColors.accentBlue),
      ('transfer', 'حوالة', Icons.swap_horiz_rounded, AppColors.accentOrange),
      ('bank', 'بنك', Icons.account_balance_rounded, Color(0xFF4F6AF0)),
      ('ewallet', 'محفظة', Icons.account_balance_wallet_rounded, AppColors.accentGreen),
      ('bank_transfer', 'حوالة مصرفية', Icons.business_rounded, Color(0xFF6A1B9A)),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 8,
      children: methods.map((m) {
        final selected = _paymentMethod == m.$1;
        return GestureDetector(
          onTap: () => setState(() {
            _paymentMethod = m.$1;
            if (m.$1 != 'ewallet') _selectedEwalletProvider = null;
            if (m.$1 != 'bank_transfer') {
              _selectedBankTransferProvider = null;
              _transferNumberController.clear();
            }
            if (m.$1 != 'ewallet' && m.$1 != 'bank_transfer') {
              _attachmentPath = null;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.fastOutSlowIn,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? m.$4.withOpacity(isDark ? 0.18 : 0.08)
                  : (isDark ? AppColors.darkSurfaceVariant : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? m.$4 : (isDark ? AppColors.darkBorder : AppColors.border),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: m.$4.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(m.$3, size: 15, color: selected ? m.$4 : AppColors.textHint),
                const SizedBox(width: 5),
                Text(
                  m.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? m.$4 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── E-wallet section ─────────────────────────────────────────────
  Widget _buildEwalletSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accentGreen.withOpacity(0.06), AppColors.accentGreen.withOpacity(0.02)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedEwalletProvider,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'اختر المحفظة الإلكترونية',
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 8),
                child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.accentGreen, size: 18),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.accentGreen.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accentGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : Colors.white,
            ),
            items: _ewalletProviders.map((p) => DropdownMenuItem<String>(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (val) => setState(() => _selectedEwalletProvider = val),
          ),
          const SizedBox(height: 10),
          _buildAttachmentButtons(),
        ],
      ),
    );
  }

  // ── Bank transfer section ────────────────────────────────────────
  Widget _buildBankTransferSection(bool isDark) {
    const purpleColor = Color(0xFF6A1B9A);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [purpleColor.withOpacity(0.06), purpleColor.withOpacity(0.02)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purpleColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedBankTransferProvider,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'اختر شركة الحوالة',
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 8),
                child: const Icon(Icons.business_rounded, color: purpleColor, size: 18),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : Colors.white,
            ),
            items: _bankTransferProviders.map((p) => DropdownMenuItem<String>(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (val) => setState(() => _selectedBankTransferProvider = val),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _transferNumberController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'رقم الحوالة (اختياري)',
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 8),
                child: const Icon(Icons.tag_rounded, color: purpleColor, size: 18),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _buildAttachmentButtons(isBankTransfer: true),
        ],
      ),
    );
  }

  // ── Attachment buttons ───────────────────────────────────────────
  Widget _buildAttachmentButtons({bool isBankTransfer = false}) {
    return Column(
      children: [
        if (_attachmentPath != null) ...[
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Image.file(File(_attachmentPath!), width: double.infinity, height: 100, fit: BoxFit.cover),
                Positioned(
                  top: 6, left: 6,
                  child: GestureDetector(
                    onTap: () => setState(() => _attachmentPath = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentBlue.withOpacity(0.3)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickImageFromGallery,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_rounded, size: 16, color: _accentBlue),
                          const SizedBox(width: 6),
                          Text(isBankTransfer ? 'رفق إشعار' : 'رفق صورة',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentBlue),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentBlue.withOpacity(0.3)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickImageFromCamera,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_rounded, size: 16, color: _accentBlue),
                          const SizedBox(width: 6),
                          Text('تصوير',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentBlue),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Cash box + Paid amount row ───────────────────────────────────
  Widget _buildCashBoxAndPaidRow(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cash box dropdown
        _buildModernDropdown<int>(
          value: _selectedCashBoxId,
          label: 'الصندوق *',
          icon: Icons.account_balance_wallet_rounded,
          items: _cashBoxes.map((cb) {
            final balance = (cb['balance'] as num?)?.toDouble() ?? 0.0;
            final bt = cb['balance_type'] as String? ?? 'credit';
            return DropdownMenuItem<int>(
              value: cb['id'] as int,
              child: Text('${cb['name']} (${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'})', style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedCashBoxId = val),
          validator: (v) => v == null ? 'يجب اختيار الصندوق' : null,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        // Paid amount + Auto-pay checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextFormField(
                controller: _paidController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.left,
                enabled: !_autoPay,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'المدفوع',
                  prefixIcon: Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: const Icon(Icons.payments_rounded, size: 18, color: _accentBlue),
                  ),
                  suffixText: _selectedCurrency,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: _autoPay,
                  fillColor: _autoPay
                      ? (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant).withOpacity(0.5)
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            // Auto-pay toggle
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _autoPay = !_autoPay;
                      if (_autoPay) {
                        _paidController.text = _total.toStringAsFixed(2);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _autoPay ? _accentBlue : (isDark ? AppColors.darkSurfaceVariant : AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _autoPay ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        width: 20, height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('مدفوع', style: context.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: _autoPay ? _accentBlue : AppColors.textHint,
                  fontWeight: _autoPay ? FontWeight.w700 : FontWeight.w400,
                )),
              ],
            ),
          ],
        ),
        // Remaining amount
        if (!_autoPay && _remaining.abs() > 0.005) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _remaining > 0.005
                  ? AppColors.error.withOpacity(0.06)
                  : AppColors.success.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _remaining > 0.005
                    ? AppColors.error.withOpacity(0.2)
                    : AppColors.success.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _remaining > 0.005 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: _remaining > 0.005 ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text('المتبقي', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                Text(
                  CurrencyFormatter.format(_remaining),
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _remaining > 0.005 ? AppColors.error : AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Entity Section (modern search with avatars) ──────────────────
  Widget _buildEntitySection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'اسم الحساب',
            icon: Icons.person_rounded,
            trailing: _isEntityRequired
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('مطلوب', style: context.textTheme.labelSmall?.copyWith(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                  )
                : Text('(اختياري)', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint, fontSize: 11)),
          ),
          // Entity selection field
          GestureDetector(
            onTap: () => setState(() => _showEntityDropdown = !_showEntityDropdown),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _showEntityDropdown
                      ? _accentBlue
                      : (_selectedEntityId != null ? _accentBlue.withOpacity(0.3) : (isDark ? AppColors.darkBorder : AppColors.border)),
                  width: _showEntityDropdown ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Avatar circle
                  _buildEntityAvatar(isDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedEntityName ?? 'اختر حساب...',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: _selectedEntityId != null
                            ? (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)
                            : AppColors.textHint,
                        fontWeight: _selectedEntityId != null ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (_selectedEntityId != null)
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedEntityId = null;
                        _selectedEntityType = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded, size: 14, color: AppColors.error),
                      ),
                    )
                  else
                    Icon(Icons.arrow_drop_down_rounded, size: 22, color: _accentBlue),
                ],
              ),
            ),
          ),
          // Dropdown with search
          if (_showEntityDropdown) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accentBlue.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: _entitySearchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'بحث عن حساب...',
                        prefixIcon: Icon(Icons.search_rounded, size: 18, color: _accentBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _accentBlue, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                      ),
                      onChanged: _filterEntities,
                    ),
                  ),
                  // Add new button
                  InkWell(
                    onTap: () => _addNewEntity(),
                    borderRadius: BorderRadius.circular(0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              gradient: _primaryGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isSale ? 'إضافة عميل جديد' : 'إضافة مورد جديد',
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: _accentBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Entity list
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _filteredEntities.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? AppColors.darkDivider : AppColors.divider),
                      itemBuilder: (context, index) {
                        final entity = _filteredEntities[index];
                        final isSelected = _selectedEntityId == entity['id'] && _selectedEntityType == entity['type'];
                        final isCustomer = entity['type'] == 'customer';
                        final balance = (entity['balance'] as num?)?.toDouble() ?? 0.0;
                        final bt = entity['balance_type'] as String? ?? 'credit';

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedEntityId = entity['id'] as int;
                              _selectedEntityType = entity['type'] as String;
                              _showEntityDropdown = false;
                              _entitySearchController.clear();
                              _filteredEntities = List.from(_combinedEntities);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            color: isSelected ? _accentBlue.withOpacity(0.06) : null,
                            child: Row(
                              children: [
                                // Avatar circle for entity
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: (isCustomer ? AppColors.success : const Color(0xFF3B82F6)).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isCustomer ? Icons.person_rounded : Icons.local_shipping_rounded,
                                    size: 16,
                                    color: isCustomer ? AppColors.success : const Color(0xFF3B82F6),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    entity['name'] ?? '',
                                    style: context.textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (balance != 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (bt == 'credit' ? AppColors.success : AppColors.error).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'}',
                                      style: context.textTheme.bodySmall?.copyWith(
                                        color: bt == 'credit' ? AppColors.success : AppColors.error,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                // Type badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isCustomer ? AppColors.success : const Color(0xFF3B82F6)).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isCustomer ? 'عميل' : 'مورد',
                                    style: context.textTheme.labelSmall?.copyWith(
                                      color: isCustomer ? AppColors.success : const Color(0xFF3B82F6),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isEntityRequired && _selectedEntityId == null && _paymentMechanism == 'credit')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 12, color: AppColors.error),
                  const SizedBox(width: 4),
                  Text('الحساب مطلوب للفاتورة الآجلة', style: context.textTheme.bodySmall?.copyWith(color: AppColors.error, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntityAvatar(bool isDark) {
    if (_selectedEntityId == null) {
      return Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.person_outline_rounded, size: 18, color: AppColors.textHint),
      );
    }
    final isCustomer = _selectedEntityType == 'customer';
    final name = _selectedEntityName ?? '';
    final initial = name.isNotEmpty ? name[0] : '?';
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCustomer
              ? [const Color(0xFF22C55E), const Color(0xFF4ADE80)]
              : [const Color(0xFF3B82F6), const Color(0xFF60A5FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isCustomer ? const Color(0xFF22C55E) : const Color(0xFF3B82F6)).withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(initial,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }

  // ── Add new entity ───────────────────────────────────────────────
  Future<void> _addNewEntity() async {
    _showEntityDropdown = false;
    _entitySearchController.clear();

    if (_isSale) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddCustomerSheet()),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddSupplierSheet()),
      );
    }

    // Reload entities after adding
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAllCustomers(),
      db.getAllSuppliers(),
    ]);
    setState(() {
      _customers = results[0];
      _suppliers = results[1];
      _buildCombinedEntities();
    });
  }

  // ── Items Section ────────────────────────────────────────────────
  Widget _buildItemsSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'الأصناف',
            icon: Icons.inventory_2_rounded,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: _primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${_items.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: _accentBlue.withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.shopping_cart_outlined, size: 28, color: _accentBlue.withOpacity(0.4)),
                    ),
                    const SizedBox(height: 10),
                    Text('لم يتم إضافة أصناف بعد',
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return InvoiceItemCard(
                item: item,
                onQuantityChanged: (qty) {
                  setState(() {
                    _items[index] = item.copyWith(quantity: qty, totalPrice: qty * item.unitPrice);
                    _updateAutoPay();
                  });
                },
                onDelete: () {
                  setState(() {
                    _items.removeAt(index);
                    _updateAutoPay();
                  });
                },
              );
            }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accentBlue.withOpacity(0.3)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _addItem,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: _accentBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(Icons.add_rounded, size: 16, color: _accentBlue),
                        ),
                        const SizedBox(width: 8),
                        Text('إضافة صنف',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary Section ──────────────────────────────────────────────
  Widget _buildSummarySection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient accent header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accentBlue.withOpacity(isDark ? 0.15 : 0.08),
                  _accentPurple.withOpacity(isDark ? 0.08 : 0.03),
                ],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    gradient: _primaryGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.summarize_rounded, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('ملخص الفاتورة',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          // Summary body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal), isDark),
                const SizedBox(height: 8),
                // Discount inline
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.discount_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('الخصم', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          suffixText: _selectedCurrency,
                          hintText: '0.00',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                        ),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        onChanged: (_) {
                          setState(() {});
                          _updateAutoPay();
                        },
                      ),
                    ),
                  ],
                ),
                if (AppConstants.defaultVatRate > 0) ...[
                  const SizedBox(height: 8),
                  _summaryRow('الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)', CurrencyFormatter.format(_taxAmount), isDark),
                ],
                // Transport inline
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('أجور النقل', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _transportChargesController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          suffixText: _selectedCurrency,
                          hintText: '0.00',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                        ),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        onChanged: (_) {
                          setState(() {});
                          _updateAutoPay();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Total divider
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, _accentBlue.withOpacity(0.2), Colors.transparent],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Total with gradient accent
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _accentBlue.withOpacity(isDark ? 0.12 : 0.06),
                        _accentPurple.withOpacity(isDark ? 0.06 : 0.02),
                      ],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accentBlue.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('الإجمالي',
                        style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(CurrencyFormatter.format(_total),
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: _accentBlue,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedCurrency != 'YER') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.info.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        _summaryRow('المعادل بالريال اليمني', '${CurrencyFormatter.format(_totalInBaseCurrency)} ر.ي', isDark,
                            valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.info)),
                        if (_paidAmount > 0.005) ...[
                          const SizedBox(height: 4),
                          _summaryRow('المدفوع (ر.ي)', '${CurrencyFormatter.format(_paidAmountInBaseCurrency)} ر.ي', isDark,
                              valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.success)),
                        ],
                        if (_remaining > 0.005) ...[
                          const SizedBox(height: 4),
                          _summaryRow('المتبقي (ر.ي)', '${CurrencyFormatter.format(_remainingInBaseCurrency)} ر.ي', isDark,
                              valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.error)),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Notes
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'ملاحظات',
                    prefixIcon: Container(
                      margin: const EdgeInsets.only(left: 8),
                      child: const Icon(Icons.edit_note_rounded, size: 18, color: _accentBlue),
                    ),
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark, {TextStyle? valueStyle, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodySmall?.copyWith(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
        )),
        Text(value, style: valueStyle ?? context.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: valueColor ?? (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
        )),
      ],
    );
  }

  // ── Add item ─────────────────────────────────────────────────────
  Future<void> _addItem() async {
    final result = await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddInvoiceItemSheet(warehouseId: _selectedWarehouseId, invoiceType: widget.invoiceType),
    );
    if (result != null) {
      setState(() {
        _items.add(result);
        _updateAutoPay();
      });
    }
  }

  // ── Save invoice ─────────────────────────────────────────────────
  Future<void> _saveInvoice() async {
    // Validate
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة صنف واحد على الأقل');
      return;
    }
    if (_isEntityRequired && _selectedEntityId == null) {
      context.showErrorSnackBar('الحساب مطلوب');
      return;
    }
    if (_paymentMechanism == 'cash' && _selectedCashBoxId == null) {
      context.showErrorSnackBar('الرجاء اختيار الصندوق');
      return;
    }
    if (_discountAmount < -0.005) {
      context.showErrorSnackBar('الخصم لا يمكن أن يكون سالباً');
      return;
    }
    if (_discountAmount > _subtotal + 0.005) {
      context.showErrorSnackBar('الخصم لا يمكن أن يتجاوز المجموع الفرعي');
      return;
    }
    if (_paidAmount < -0.005) {
      context.showErrorSnackBar('المبلغ المدفوع لا يمكن أن يكون سالباً');
      return;
    }
    if (_paidAmount > _total + 0.005) {
      context.showErrorSnackBar('المبلغ المدفوع لا يمكن أن يتجاوز الإجمالي');
      return;
    }
    // Return invoices must be linked to an original invoice
    if (_isReturn && _originalInvoiceId == null) {
      context.showErrorSnackBar('يجب ربط الفاتورة المرتجعة بالفاتورة الأصلية');
      return;
    }

    // Check return limits if this is a return invoice with an original invoice linked
    if (_isReturn && _originalInvoiceId != null) {
      final db = DatabaseHelper();
      final itemsMaps = _items.map((item) => <String, dynamic>{
        'product_id': item.productId,
        'product_name': item.productName,
        'quantity': item.quantity,
        'base_quantity': item.baseQuantity,
        'unit_price': item.unitPrice,
        'total_price': item.totalPrice,
      }).toList();
      final limitErrors = await db.checkReturnLimits(_originalInvoiceId, itemsMaps);
      if (limitErrors.isNotEmpty && mounted) {
        final errorMessages = limitErrors.values.join('\n');
        showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('تجاوز حد المرتجع'),
                ],
              ),
              content: Text(errorMessages),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('موافق'),
                ),
              ],
            ),
          ),
        );
        return;
      }
    }

    // Determine effective payment mechanism for journal entries
    final effectivePaymentMechanism = _paymentMechanism;
    final effectivePaidAmount = _paymentMechanism == 'credit' ? 0.0 : _paidAmount;

    final invoiceId = const Uuid().v4();
    final invoice = Invoice(
      id: invoiceId,
      type: widget.invoiceType,
      paymentMechanism: _paymentMechanism,
      paymentMethod: _paymentMethod,
      isReturn: _isReturn,
      cashBoxId: _paymentMechanism == 'cash' ? _selectedCashBoxId : null,
      customerId: _selectedEntityType == 'customer' ? _selectedEntityId : null,
      supplierId: _selectedEntityType == 'supplier' ? _selectedEntityId : null,
      subtotal: _subtotal,
      discountRate: _subtotal > 0 ? (_discountAmount / _subtotal) * 100 : 0.0,
      discountAmount: _discountAmount,
      taxAmount: _taxAmount,
      total: _total,
      paidAmount: _paidAmount,
      remaining: _remaining,
      status: _remaining <= 0.005 ? 'paid' : _paidAmount > 0.005 ? 'partial' : 'unpaid',
      warehouseId: _selectedWarehouseId,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      currency: _selectedCurrency,
      exchangeRate: _selectedExchangeRate,
      ewalletProvider: _paymentMethod == 'ewallet' ? _selectedEwalletProvider : null,
      bankTransferProvider: _paymentMethod == 'bank_transfer' ? _selectedBankTransferProvider : null,
      transferNumber: _paymentMethod == 'bank_transfer' && _transferNumberController.text.isNotEmpty
          ? _transferNumberController.text
          : null,
      attachmentPath: (_paymentMethod == 'ewallet' || _paymentMethod == 'bank_transfer')
          ? _attachmentPath
          : null,
      originalInvoiceId: _isReturn ? _originalInvoiceId : null,
    );

    final itemsMaps = _items.map((item) => {
      'invoice_id': invoiceId,
      'product_id': item.productId,
      'product_name': item.productName,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'total_price': item.totalPrice,
      'unit_name': item.unitName,
      'conversion_factor': item.conversionFactor,
      'base_quantity': item.baseQuantity,
      'notes': item.notes,
    }).toList();

    final db = DatabaseHelper();

    await db.saveInvoiceWithJournalEntries(
      invoice.toMap(),
      itemsMaps,
      invoiceType: invoice.effectiveType,
      paymentMechanism: effectivePaymentMechanism,
      isReturn: _isReturn,
      cashBoxId: _paymentMechanism == 'cash' ? _selectedCashBoxId : null,
      transportCharges: _transportCharges,
      paidAmount: effectivePaidAmount,
    );

    // Update shift totals if this is a return invoice and a shift is active
    if (_isReturn && _selectedCashBoxId != null) {
      try {
        final activeShift = await db.getActiveShift(_selectedCashBoxId!);
        if (activeShift != null) {
          final shiftId = activeShift['id'] as int;
          await db.updateShiftTotals(shiftId, 0.0, _total, 0.0);
        }
      } catch (e) {
        debugPrint('Warning: Could not update shift totals for return: $e');
      }
    }

    if (mounted) {
      context.showSuccessSnackBar('تم حفظ الفاتورة بنجاح');
      Navigator.pop(context);
    }
  }

  // ── Share invoice details ────────────────────────────────────────
  void _shareInvoice() {
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة أصناف أولاً');
      return;
    }
    final entityName = _selectedEntityName ?? '—';
    final buffer = StringBuffer();
    buffer.writeln(_title);
    buffer.writeln('──────────────────');
    buffer.writeln('الحساب: $entityName');
    buffer.writeln('المجموع الفرعي: ${CurrencyFormatter.format(_subtotal)}');
    if (_discountAmount > 0) buffer.writeln('الخصم: ${CurrencyFormatter.format(_discountAmount)}');
    if (_taxAmount > 0) buffer.writeln('الضريبة: ${CurrencyFormatter.format(_taxAmount)}');
    if (_transportCharges > 0) buffer.writeln('أجور النقل: ${CurrencyFormatter.format(_transportCharges)}');
    buffer.writeln('الإجمالي: ${CurrencyFormatter.format(_total)}');
    buffer.writeln('المدفوع: ${CurrencyFormatter.format(_paidAmount)}');
    buffer.writeln('المتبقي: ${CurrencyFormatter.format(_remaining)}');
    buffer.writeln('──────────────────');
    buffer.writeln('الأصناف:');
    for (final item in _items) {
      buffer.writeln('  ${item.productName} × ${item.quantity} = ${CurrencyFormatter.format(item.totalPrice)}');
    }
    if (_notesController.text.isNotEmpty) buffer.writeln('ملاحظات: ${_notesController.text}');
    Share.share(buffer.toString(), subject: _title);
  }

  // ── Share via WhatsApp ───────────────────────────────────────────
  void _shareInvoiceWhatsApp() {
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة أصناف أولاً');
      return;
    }
    final entityName = _selectedEntityName ?? '—';
    final buffer = StringBuffer();
    buffer.writeln('*$_title*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('الحساب: *$entityName*');
    buffer.writeln('المجموع الفرعي: ${CurrencyFormatter.format(_subtotal)}');
    if (_discountAmount > 0) buffer.writeln('الخصم: ${CurrencyFormatter.format(_discountAmount)}');
    if (_taxAmount > 0) buffer.writeln('الضريبة: ${CurrencyFormatter.format(_taxAmount)}');
    if (_transportCharges > 0) buffer.writeln('أجور النقل: ${CurrencyFormatter.format(_transportCharges)}');
    buffer.writeln('*الإجمالي: ${CurrencyFormatter.format(_total)}*');
    buffer.writeln('المدفوع: ${CurrencyFormatter.format(_paidAmount)}');
    buffer.writeln('المتبقي: ${CurrencyFormatter.format(_remaining)}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('*الأصناف:*');
    for (final item in _items) {
      buffer.writeln('▫️ ${item.productName} × ${item.quantity} = ${CurrencyFormatter.format(item.totalPrice)}');
    }
    if (_notesController.text.isNotEmpty) buffer.writeln('ملاحظات: ${_notesController.text}');
    Share.share(buffer.toString(), subject: _title);
  }

  // ── Print invoice ────────────────────────────────────────────────
  Future<void> _printInvoice() async {
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة أصناف أولاً');
      return;
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري إنشاء ملف PDF...'), duration: Duration(seconds: 1)),
      );
      final entityName = _selectedEntityName ?? '—';

      final invoiceMap = <String, dynamic>{
        'id': '—',
        'type': widget.invoiceType,
        'is_return': 0,
        'customer_id': _selectedEntityId,
        'subtotal': _subtotal,
        'discount_amount': _discountAmount,
        'tax_amount': _taxAmount,
        'transport_charges': _transportCharges,
        'total': _total,
        'paid_amount': _paidAmount,
        'remaining': _remaining,
        'status': _remaining <= 0 ? 'paid' : 'unpaid',
        'payment_method': _paymentMethod,
        'currency': _selectedCurrency,
        'notes': _notesController.text,
        'entity_name': entityName,
        'created_at': DateTime.now().toIso8601String(),
      };

      final itemsMap = _items.map((item) => <String, dynamic>{
        'product_name': item.productName,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total_price': item.totalPrice,
        'unit_name': item.unitName,
        'base_quantity': item.baseQuantity,
      }).toList();

      await InvoicePdfGenerator.printInvoice(invoiceMap, itemsMap);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('خطأ في الطباعة: $e');
    }
  }

  /// Print via Bluetooth thermal printer.
  Future<void> _printBluetooth() async {
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة أصناف أولاً');
      return;
    }

    final printerService = BluetoothPrinterService.instance;

    if (!printerService.isConnected) {
      final connected = await printerService.autoConnect();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('الطابعة غير متصلة. يرجى الذهاب إلى الإعدادات لتوصيلها'),
              backgroundColor: AppColors.warning,
              action: SnackBarAction(
                label: 'الإعدادات',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothPrinterSettingsScreen()));
                },
              ),
            ),
          );
        }
        return;
      }
    }

    try {
      final entityName = _selectedEntityName ?? '—';
      final currencySymbol = _selectedCurrency == 'SAR' ? 'ر.س' : _selectedCurrency == 'USD' ? r'$' : 'ر.ي';

      await printerService.printReceipt({
        'invoice_number': '—',
        'invoice_type': _isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات',
        'date': DateTime.now(),
        'customer_name': entityName,
        'items': _items.map((item) => <String, dynamic>{
          'product_name': item.productName,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total_price': item.totalPrice,
          'unit_name': item.unitName,
          'base_quantity': item.baseQuantity,
        }).toList(),
        'subtotal': _subtotal,
        'discount': _discountAmount,
        'tax': _taxAmount,
        'total': _total,
        'paid': _paidAmount,
        'remaining': _remaining,
        'currency': currencySymbol,
        'notes': _notesController.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الفاتورة للطابعة الحرارية'), backgroundColor: AppColors.success),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) context.showErrorSnackBar(e.message);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('خطأ في الطباعة الحرارية: $e');
    }
  }
}
