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
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../settings/bluetooth_printer_settings_screen.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/invoice_model.dart';
import '../../widgets/invoice_item_card.dart';
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

  // Payment mechanism: cash or credit
  String _paymentMechanism = 'cash';
  // Payment method: cash, check, transfer, bank, ewallet, bank_transfer
  String _paymentMethod = 'cash';
  // Is return invoice
  bool _isReturn = false;
  // Auto-pay toggle
  bool _autoPay = true;

  int? _selectedEntityId; // customer or supplier
  int? _selectedWarehouseId;
  int? _selectedCashBoxId;
  final List<InvoiceItem> _items = [];

  // E-wallet state
  String? _selectedEwalletProvider;
  // Bank transfer state
  String? _selectedBankTransferProvider;
  // Attachment image
  String? _attachmentPath;

  // Accordion section state
  bool _section1Expanded = true; // Currency & Return
  bool _section2Expanded = true; // Payment Info
  bool _section3Expanded = true; // Entity
  bool _section4Expanded = true; // Items
  bool _section5Expanded = true; // Summary

  // Data from DB
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  List<Map<String, dynamic>> _currencies = [];
  String _selectedCurrency = 'YER';
  double _selectedExchangeRate = 1.0;
  bool _isLoading = true;

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
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _transportChargesController.dispose();
    _transferNumberController.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  double get _discountAmount => double.tryParse(_discountController.text) ?? 0;
  double get _transportCharges => double.tryParse(_transportChargesController.text) ?? 0;
  double get _taxAmount => (_subtotal - _discountAmount) * (AppConstants.defaultVatRate / 100);
  double get _total => _subtotal - _discountAmount + _taxAmount + _transportCharges;
  double get _paidAmount => double.tryParse(_paidController.text) ?? 0;
  double get _remaining => _total - _paidAmount;

  void _updateAutoPay() {
    if (_autoPay && _total > 0) {
      _paidController.text = _total.toStringAsFixed(2);
    }
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            IconButton(
              onPressed: _saveInvoice,
              icon: const Icon(Icons.save),
              tooltip: 'حفظ',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Partial payment warning banner
                            if (!_autoPay && _paymentMechanism == 'cash' && _paidAmount > 0 && _remaining > 0.005)
                              _buildPartialPaymentWarning(),
                            _buildSection1CurrencyAndReturn(),
                            _buildSection2PaymentInfo(),
                            _buildSection3Entity(),
                            _buildSection4Items(),
                            _buildSection5SummaryAndNotes(),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomBar(),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Partial payment warning ──────────────────────────────────────
  Widget _buildPartialPaymentWarning() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: AppColors.warning, size: 22),
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

  // ── Section 1: Currency & Return ─────────────────────────────────
  Widget _buildSection1CurrencyAndReturn() {
    return _AccordionSection(
      title: 'نوع الفاتورة والعملة',
      icon: Icons.monetization_on,
      color: AppColors.primary,
      isExpanded: _section1Expanded,
      onToggle: () => setState(() => _section1Expanded = !_section1Expanded),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedCurrency,
            decoration: const InputDecoration(
              labelText: 'العملة',
              prefixIcon: Icon(Icons.monetization_on),
            ),
            items: _currencies.map((c) => DropdownMenuItem<String>(
              value: c['code'] as String,
              child: Text('${c['code']} (${c['symbol']}) - سعر الصرف: ${(c['exchange_rate'] as num?)?.toDouble() ?? 1.0}', style: const TextStyle(fontSize: 13)),
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
          ),
          const SizedBox(height: 8),
          Text(
            'سعر الصرف: $_selectedExchangeRate',
            style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _isReturn,
            onChanged: (v) => setState(() => _isReturn = v ?? false),
            title: Text('فاتورة مرتجع', style: context.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _isReturn ? AppColors.error : null,
            )),
            subtitle: _isReturn ? Text('سيتم تحويل الفاتورة إلى فاتورة مرتجع', style: context.textTheme.bodySmall?.copyWith(color: AppColors.error)) : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.error,
            dense: true,
          ),
        ],
      ),
    );
  }

  // ── Section 2: Payment Info (always expanded) ────────────────────
  Widget _buildSection2PaymentInfo() {
    return _AccordionSection(
      title: 'معلومات الدفع',
      icon: Icons.account_balance_wallet,
      color: AppColors.success,
      isExpanded: _section2Expanded,
      onToggle: () => setState(() => _section2Expanded = !_section2Expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payment mechanism cards
          Row(
            children: [
              Expanded(
                child: _PaymentOptionCard(
                  icon: Icons.payments,
                  label: 'نقداً',
                  subtitle: 'دفع فوري',
                  isSelected: _paymentMechanism == 'cash',
                  color: AppColors.success,
                  onTap: () => setState(() => _paymentMechanism = 'cash'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PaymentOptionCard(
                  icon: Icons.access_time,
                  label: 'أجل',
                  subtitle: 'دفع لاحق',
                  isSelected: _paymentMechanism == 'credit',
                  color: AppColors.accentOrange,
                  onTap: () => setState(() {
                    _paymentMechanism = 'credit';
                    _selectedCashBoxId = null;
                    _autoPay = false;
                    _paidController.text = '0';
                  }),
                ),
              ),
            ],
          ),
          // If credit, show info banner
          if (_paymentMechanism == 'credit') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.accentOrange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الفاتورة الآجلة: سيتم تسجيل المبلغ كرصيد على ${_isSale ? "العميل" : "المورد"}',
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Payment method (only when cash)
          if (_paymentMechanism == 'cash') ...[
            const SizedBox(height: 16),
            Text('طريقة الدفع', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _buildPaymentMethodGrid(),
          ],
          // E-wallet / bank transfer sections
          if (_paymentMechanism == 'cash' && _paymentMethod == 'ewallet')
            _buildEwalletSection(),
          if (_paymentMechanism == 'cash' && _paymentMethod == 'bank_transfer')
            _buildBankTransferSection(),
          // Cash box
          const SizedBox(height: 16),
          _buildCashBoxDropdown(),
          // Auto-pay toggle + paid amount
          if (_paymentMechanism == 'cash') ...[
            const SizedBox(height: 16),
            _buildAutoPayAndPaidAmount(),
          ],
        ],
      ),
    );
  }

  // ── Payment method grid ──────────────────────────────────────────
  Widget _buildPaymentMethodGrid() {
    const methods = [
      ('cash', 'نقدي', Icons.payments, AppColors.success),
      ('check', 'شيك', Icons.sticky_note_2, AppColors.accentBlue),
      ('transfer', 'حوالة', Icons.swap_horiz, AppColors.accentOrange),
      ('bank', 'بنك', Icons.account_balance, AppColors.primary),
      ('ewallet', 'محفظة إلكترونية', Icons.account_balance_wallet, AppColors.accentGreen),
      ('bank_transfer', 'حوالة مصرفية', Icons.business, Color(0xFF6A1B9A)),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: methods.map((m) {
        final selected = _paymentMethod == m.$1;
        return _PaymentMethodChip(
          icon: m.$3,
          label: m.$2,
          color: m.$4,
          isSelected: selected,
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
        );
      }).toList(),
    );
  }

  // ── E-wallet section ─────────────────────────────────────────────
  Widget _buildEwalletSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet, size: 20, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Text('محافظ إلكترونية', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.accentGreen)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedEwalletProvider,
            decoration: InputDecoration(
              labelText: 'اختر المحفظة الإلكترونية',
              prefixIcon: const Icon(Icons.account_balance_wallet, color: AppColors.accentGreen),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _ewalletProviders.map((p) => DropdownMenuItem<String>(value: p, child: Text(p, style: const TextStyle(fontSize: 14)))).toList(),
            onChanged: (val) => setState(() => _selectedEwalletProvider = val),
          ),
          const SizedBox(height: 16),
          Text('إرفاق صورة إيصال الدفع (اختياري)', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildAttachmentButtons(),
        ],
      ),
    );
  }

  // ── Bank transfer section ────────────────────────────────────────
  Widget _buildBankTransferSection() {
    const purpleColor = Color(0xFF6A1B9A);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: purpleColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: purpleColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.business, size: 20, color: purpleColor),
              const SizedBox(width: 8),
              Text('حوالات مصرفية', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: purpleColor)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedBankTransferProvider,
            decoration: InputDecoration(
              labelText: 'اختر شركة الحوالة',
              prefixIcon: const Icon(Icons.business, color: purpleColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _bankTransferProviders.map((p) => DropdownMenuItem<String>(value: p, child: Text(p, style: const TextStyle(fontSize: 14)))).toList(),
            onChanged: (val) => setState(() => _selectedBankTransferProvider = val),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _transferNumberController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'رقم الحوالة (اختياري)',
              prefixIcon: const Icon(Icons.tag, color: purpleColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          Text('إرفاق صورة إشعار الحوالة (اختياري)', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
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
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Image.file(File(_attachmentPath!), width: double.infinity, height: 120, fit: BoxFit.cover),
                Positioned(
                  top: 4, left: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _attachmentPath = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.close, size: 18, color: Colors.white),
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
              child: OutlinedButton.icon(
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.image, size: 18),
                label: Text(isBankTransfer ? 'رفق صورة الإشعار' : 'رفق صورة', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImageFromCamera,
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('تصوير', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Cash box dropdown ────────────────────────────────────────────
  Widget _buildCashBoxDropdown() {
    final isCash = _paymentMechanism == 'cash';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet, size: 20, color: isCash ? AppColors.primary : AppColors.textHint),
            const SizedBox(width: 8),
            Text('حساب الصندوق', style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isCash ? null : AppColors.textHint,
            )),
            if (!isCash) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('معطل - فاتورة آجلة', style: context.textTheme.labelSmall?.copyWith(color: AppColors.warning, fontSize: 10)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: isCash ? _selectedCashBoxId : null,
          decoration: InputDecoration(
            hintText: isCash ? 'اختر الصندوق *' : 'غير متاح',
            prefixIcon: Icon(Icons.account_balance_wallet, color: isCash ? null : AppColors.textHint),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
            ),
          ),
          items: isCash ? _cashBoxes.map((cb) {
            final balance = (cb['balance'] as num?)?.toDouble() ?? 0.0;
            final bt = cb['balance_type'] as String? ?? 'credit';
            return DropdownMenuItem<int>(
              value: cb['id'] as int,
              child: Text('${cb['name']} (${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'})'),
            );
          }).toList() : [],
          onChanged: isCash ? (val) => setState(() => _selectedCashBoxId = val) : null,
          validator: isCash ? (v) => v == null ? 'يجب اختيار الصندوق' : null : null,
        ),
      ],
    );
  }

  // ── Auto-pay toggle + paid amount ────────────────────────────────
  Widget _buildAutoPayAndPaidAmount() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Auto-pay toggle
          Row(
            children: [
              const Icon(Icons.auto_fix_high, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('دفع تلقائي', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: _autoPay,
                onChanged: (val) {
                  setState(() {
                    _autoPay = val;
                    if (_autoPay) {
                      _paidController.text = _total.toStringAsFixed(2);
                    }
                  });
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
          Text(
            _autoPay ? 'سيتم تسجيل المبلغ بالكامل كمدفوع' : 'يمكنك إدخال مبلغ جزئي',
            style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          // Paid amount field
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المدفوع', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _paidController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  enabled: !_autoPay,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixText: AppConstants.currency,
                    hintText: '0.00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: !_autoPay,
                    fillColor: _autoPay ? AppColors.surfaceVariant.withValues(alpha: 0.5) : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Remaining
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المتبقي', style: context.textTheme.bodyMedium),
              Text(
                CurrencyFormatter.format(_remaining),
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _remaining > 0.005 ? AppColors.error : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section 3: Entity ────────────────────────────────────────────
  Widget _buildSection3Entity() {
    final entities = _isSale ? _customers : _suppliers;
    final label = _isSale ? 'العميل' : 'المورد';

    return _AccordionSection(
      title: '$label${_isEntityRequired ? ' *' : ''}',
      icon: _isSale ? Icons.person : Icons.business,
      color: _isSale ? AppColors.success : AppColors.info,
      isExpanded: _section3Expanded,
      onToggle: () => setState(() => _section3Expanded = !_section3Expanded),
      trailing: !_isEntityRequired
          ? Text('(اختياري)', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint))
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text('مطلوب', style: context.textTheme.labelSmall?.copyWith(color: AppColors.error, fontSize: 10)),
            ),
      child: Column(
        children: [
          DropdownButtonFormField<int>(
            value: _selectedEntityId,
            decoration: InputDecoration(
              hintText: 'اختر $label',
              prefixIcon: Icon(_isSale ? Icons.person : Icons.business),
            ),
            items: entities.map((e) {
              final balance = (e['balance'] as num?)?.toDouble() ?? 0.0;
              final bt = e['balance_type'] as String? ?? 'credit';
              String balanceStr = '';
              if (balance != 0) {
                balanceStr = ' (${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'})';
              }
              return DropdownMenuItem<int>(
                value: e['id'] as int,
                child: Text('${e['name']}$balanceStr', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedEntityId = val),
            validator: _isEntityRequired ? (v) => v == null ? _isEntityRequiredMsg : null : null,
          ),
        ],
      ),
    );
  }

  String get _isEntityRequiredMsg {
    final label = _isSale ? 'العميل' : 'المورد';
    if (_paymentMechanism == 'credit') return '$label مطلوب للفاتورة الآجلة';
    return '$label مطلوب عند وجود مبلغ متبقي';
  }

  // ── Section 4: Items ─────────────────────────────────────────────
  Widget _buildSection4Items() {
    return _AccordionSection(
      title: 'الأصناف',
      icon: Icons.inventory_2,
      color: AppColors.primary,
      isExpanded: _section4Expanded,
      onToggle: () => setState(() => _section4Expanded = !_section4Expanded),
      trailing: Text('${_items.length} صنف', style: context.textTheme.bodySmall),
      child: Column(
        children: [
          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.dividerColor, style: BorderStyle.solid),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.shopping_cart, size: 48, color: AppColors.textHint),
                    const SizedBox(height: 8),
                    Text('لم يتم إضافة أصناف بعد', style: context.textTheme.bodyMedium),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_circle),
              label: const Text('إضافة صنف'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 5: Summary & Notes ───────────────────────────────────
  Widget _buildSection5SummaryAndNotes() {
    return _AccordionSection(
      title: 'الملخص والملاحظات',
      icon: Icons.summarize,
      color: AppColors.accentOrange,
      isExpanded: _section5Expanded,
      onToggle: () => setState(() => _section5Expanded = !_section5Expanded),
      child: Column(
        children: [
          _summaryRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الخصم', style: context.textTheme.bodyMedium),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _discountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixText: AppConstants.currency,
                    hintText: '0.00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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
            _summaryRow('الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)', CurrencyFormatter.format(_taxAmount)),
          ],
          // Transport
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('أجور النقل', style: context.textTheme.bodyMedium),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _transportChargesController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixText: AppConstants.currency,
                    hintText: '0.00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _updateAutoPay();
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _summaryRow('الإجمالي', CurrencyFormatter.format(_total),
              valueStyle: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
          if (_selectedCurrency != 'YER') ...[
            const SizedBox(height: 4),
            _summaryRow('بالعملة الأساسية', CurrencyFormatter.format(_total * _selectedExchangeRate),
                valueStyle: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 8),
          _summaryRow('المدفوع', CurrencyFormatter.format(_paidAmount), valueColor: AppColors.success),
          const SizedBox(height: 4),
          _summaryRow('المتبقي', CurrencyFormatter.format(_remaining),
              valueStyle: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _remaining > 0.005 ? AppColors.error : AppColors.success,
              )),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظات',
              prefixIcon: Icon(Icons.edit_note),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {TextStyle? valueStyle, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium),
        Text(value, style: valueStyle ?? context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: valueColor)),
      ],
    );
  }

  // ── Bottom action bar ────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: _shareInvoiceWhatsApp,
              icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
              tooltip: 'واتساب',
            ),
            IconButton.outlined(
              onPressed: _shareInvoice,
              icon: const Icon(Icons.share),
              tooltip: 'مشاركة',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _printInvoice,
                icon: const Icon(Icons.print),
                label: const Text('طباعة'),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.outlined(
              onPressed: _printBluetooth,
              icon: const Icon(Icons.bluetooth, color: AppColors.primary),
              tooltip: 'طباعة حرارية',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveInvoice,
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add item ─────────────────────────────────────────────────────
  Future<void> _addItem() async {
    final result = await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddInvoiceItemSheet(warehouseId: _selectedWarehouseId),
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
      context.showErrorSnackBar(_isEntityRequiredMsg);
      return;
    }
    if (_paymentMechanism == 'cash' && _selectedCashBoxId == null) {
      context.showErrorSnackBar('الرجاء اختيار حساب الصندوق');
      return;
    }
    if (_paidAmount > _total + 0.005) {
      context.showErrorSnackBar('المبلغ المدفوع لا يمكن أن يتجاوز الإجمالي');
      return;
    }

    // Determine effective payment mechanism for journal entries
    // If cash mechanism but paid < total, this is a split: some cash, some credit
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
      customerId: _isSale ? _selectedEntityId : null,
      supplierId: !_isSale ? _selectedEntityId : null,
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
    );

    final itemsMaps = _items.map((item) => {
      'invoice_id': invoiceId,
      'product_id': item.productId,
      'product_name': item.productName,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'total_price': item.totalPrice,
      'notes': item.notes,
    }).toList();

    final db = DatabaseHelper();

    // For partial payments at creation time (cash + remaining on credit),
    // we need to pass the paid amount as the effective amount for cash journal entries.
    // The saveInvoiceWithJournalEntries method needs to be told the split.
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
    final entityName = _isSale
        ? (_customers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—')
        : (_suppliers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—');
    final buffer = StringBuffer();
    buffer.writeln(_title);
    buffer.writeln('──────────────────');
    buffer.writeln('${_isSale ? 'العميل' : 'المورد'}: $entityName');
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
    final entityName = _isSale
        ? (_customers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—')
        : (_suppliers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—');
    final buffer = StringBuffer();
    buffer.writeln('*$_title*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('${_isSale ? 'العميل' : 'المورد'}: *$entityName*');
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
      final entityName = _isSale
          ? (_customers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—')
          : (_suppliers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—');

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
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const _BluetoothSettingsWrapper()));
                },
              ),
            ),
          );
        }
        return;
      }
    }

    try {
      final entityName = _isSale
          ? (_customers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—')
          : (_suppliers.where((e) => e['id'] == _selectedEntityId).firstOrNull?['name'] ?? '—');

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

// ═══════════════════════════════════════════════════════════════════════════
//  ACCORDION SECTION WIDGET
// ═══════════════════════════════════════════════════════════════════════════
class _AccordionSection extends StatelessWidget {
  const _AccordionSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color color;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isExpanded ? color.withValues(alpha: 0.3) : context.dividerColor),
        boxShadow: isExpanded
            ? [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (trailing != null) trailing!,
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_left, color: color, size: 22),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  BLUETOOTH SETTINGS WRAPPER
// ═══════════════════════════════════════════════════════════════════════════
class _BluetoothSettingsWrapper extends StatelessWidget {
  const _BluetoothSettingsWrapper();

  @override
  Widget build(BuildContext context) {
    return BluetoothPrinterSettingsScreen();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAYMENT OPTION CARD
// ═══════════════════════════════════════════════════════════════════════════
class _PaymentOptionCard extends StatelessWidget {
  const _PaymentOptionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : context.dividerColor, width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: isSelected ? color : AppColors.textHint),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? color : AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? color.withValues(alpha: 0.7) : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle, size: 18, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAYMENT METHOD CHIP
// ═══════════════════════════════════════════════════════════════════════════
class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : context.dividerColor, width: isSelected ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: isSelected ? color : AppColors.textHint),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
