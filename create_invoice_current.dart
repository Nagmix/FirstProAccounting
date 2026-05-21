import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
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

  // Unused but kept for potential future use
  // ignore: unused_element
  String _getEntityBalanceText(int? entityId) {
    if (entityId == null) return '';
    final entities = _isSale ? _customers : _suppliers;
    final entity = entities.where((e) => e['id'] == entityId).firstOrNull;
    if (entity == null) return '';
    final balance = (entity['balance'] as num?)?.toDouble() ?? 0.0;
    final balanceType = entity['balance_type'] as String? ?? 'credit';
    if (balance == 0) return '';
    final isCredit = balanceType == 'credit';
    return '(${CurrencyFormatter.format(balance)} ${isCredit ? 'له' : 'عليه'})';
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
              icon: const Icon(PhosphorIconsRegular.floppyDisk),
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
                            _buildCurrencySection(),
                            _buildReturnCheckbox(),
                            _buildPaymentMechanismSection(),
                            if (_paymentMechanism == 'cash') _buildPaymentMethodSection(),
                            if (_paymentMechanism == 'cash' && _paymentMethod == 'ewallet')
                              _buildEwalletSection(),
                            if (_paymentMechanism == 'cash' && _paymentMethod == 'bank_transfer')
                              _buildBankTransferSection(),
                            _buildCashBoxSection(),
                            _buildEntitySection(),
                            _buildWarehouseSection(),
                            _buildItemsSection(),
                            _buildTransportChargesSection(),
                            _buildSummarySection(),
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

  // ── Currency section ──────────────────────────────────────────
  Widget _buildCurrencySection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.coin, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('العملة', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCurrency,
            decoration: const InputDecoration(
              labelText: 'العملة',
              prefixIcon: Icon(PhosphorIconsRegular.coin),
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
            'سعر الصرف: $_selectedExchangeRate (من الإعدادات)',
            style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Return checkbox ──────────────────────────────────────────
  Widget _buildReturnCheckbox() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isReturn ? AppColors.error.withValues(alpha: 0.08) : context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isReturn ? AppColors.error.withValues(alpha: 0.3) : context.dividerColor,
        ),
      ),
      child: CheckboxListTile(
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
    );
  }

  // ── Payment mechanism (cash or credit) ───────────────────────
  Widget _buildPaymentMechanismSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.wallet, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('آلية الدفع', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PaymentOptionCard(
                  icon: PhosphorIconsFill.money,
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
                  icon: PhosphorIconsFill.clock,
                  label: 'أجل',
                  subtitle: 'دفع لاحق',
                  isSelected: _paymentMechanism == 'credit',
                  color: AppColors.accentOrange,
                  onTap: () => setState(() {
                    _paymentMechanism = 'credit';
                    _selectedCashBoxId = null;
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Payment method (cash, check, transfer, bank, ewallet, bank_transfer) ──
  Widget _buildPaymentMethodSection() {
    const methods = [
      ('cash', 'نقدي', PhosphorIconsFill.money, AppColors.success),
      ('check', 'شيك', PhosphorIconsFill.note, AppColors.accentBlue),
      ('transfer', 'حوالة', PhosphorIconsFill.arrowsLeftRight, AppColors.accentOrange),
      ('bank', 'بنك', PhosphorIconsFill.bank, AppColors.primary),
      ('ewallet', 'محفظة إلكترونية', PhosphorIconsFill.wallet, AppColors.accentGreen),
      ('bank_transfer', 'حوالة مصرفية', PhosphorIconsFill.buildings, Color(0xFF6A1B9A)),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.creditCard, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('طريقة الدفع', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
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
                  // Reset provider selections when switching method
                  if (m.$1 != 'ewallet') {
                    _selectedEwalletProvider = null;
                  }
                  if (m.$1 != 'bank_transfer') {
                    _selectedBankTransferProvider = null;
                    _transferNumberController.clear();
                  }
                  // Reset attachment when switching away from ewallet/bank_transfer
                  if (m.$1 != 'ewallet' && m.$1 != 'bank_transfer') {
                    _attachmentPath = null;
                  }
                }),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── E-wallet section ─────────────────────────────────────────
  Widget _buildEwalletSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              Icon(PhosphorIconsFill.wallet, size: 20, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Text('محافظ إلكترونية', style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.accentGreen,
              )),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedEwalletProvider,
            decoration: InputDecoration(
              labelText: 'اختر المحفظة الإلكترونية',
              prefixIcon: const Icon(PhosphorIconsRegular.wallet, color: AppColors.accentGreen),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _ewalletProviders.map((p) => DropdownMenuItem<String>(
              value: p,
              child: Text(p, style: const TextStyle(fontSize: 14)),
            )).toList(),
            onChanged: (val) => setState(() => _selectedEwalletProvider = val),
          ),
          const SizedBox(height: 16),
          Text(
            'إرفاق صورة إيصال الدفع (اختياري)',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildAttachmentButtons(),
        ],
      ),
    );
  }

  // ── Bank transfer section ────────────────────────────────────
  Widget _buildBankTransferSection() {
    const purpleColor = Color(0xFF6A1B9A);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              const Icon(PhosphorIconsFill.buildings, size: 20, color: purpleColor),
              const SizedBox(width: 8),
              Text('حوالات مصرفية', style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: purpleColor,
              )),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedBankTransferProvider,
            decoration: InputDecoration(
              labelText: 'اختر شركة الحوالة',
              prefixIcon: const Icon(PhosphorIconsRegular.buildings, color: purpleColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _bankTransferProviders.map((p) => DropdownMenuItem<String>(
              value: p,
              child: Text(p, style: const TextStyle(fontSize: 14)),
            )).toList(),
            onChanged: (val) => setState(() => _selectedBankTransferProvider = val),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _transferNumberController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'رقم الحوالة (اختياري)',
              prefixIcon: const Icon(PhosphorIconsRegular.hash, color: purpleColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'إرفاق صورة إشعار الحوالة (اختياري)',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildAttachmentButtons(isBankTransfer: true),
        ],
      ),
    );
  }

  // ── Attachment buttons (shared between ewallet & bank_transfer) ──
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
                Image.file(
                  File(_attachmentPath!),
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _attachmentPath = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
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
                icon: const Icon(PhosphorIconsRegular.image, size: 18),
                label: Text(
                  isBankTransfer ? 'رفق صورة الإشعار من المعرض' : 'رفق صورة من المعرض',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImageFromCamera,
                icon: const Icon(PhosphorIconsRegular.camera, size: 18),
                label: const Text('تصوير عبر الكاميرا', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Cash box dropdown (always visible, disabled when credit) ─
  Widget _buildCashBoxSection() {
    final isCash = _paymentMechanism == 'cash';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCash ? context.surfaceColor : context.surfaceColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCash ? context.dividerColor : AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.vault, size: 20, color: isCash ? AppColors.primary : AppColors.textHint),
              const SizedBox(width: 8),
              Text('حساب الصندوق', style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isCash ? null : AppColors.textHint,
              )),
              if (!isCash) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('معطل - فاتورة آجلة', style: context.textTheme.labelSmall?.copyWith(color: AppColors.warning, fontSize: 10)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: isCash ? _selectedCashBoxId : null,
            decoration: InputDecoration(
              hintText: isCash ? 'اختر الصندوق *' : 'غير متاح للفاتورة الآجلة',
              prefixIcon: Icon(PhosphorIconsRegular.vault, color: isCash ? null : AppColors.textHint),
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
            validator: isCash ? (v) => v == null ? 'يجب اختيار الصندوق للفاتورة النقدية' : null : null,
          ),
        ],
      ),
    );
  }

  // ── Customer/Supplier section ────────────────────────────────
  Widget _buildEntitySection() {
    final entities = _isSale ? _customers : _suppliers;
    final label = _isSale ? 'العميل' : 'المورد';
    final isRequired = _paymentMechanism == 'credit';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$label${isRequired ? ' *' : ''}', style: context.textTheme.titleSmall),
              const Spacer(),
              if (!isRequired) Text('(اختياري)', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _selectedEntityId,
            decoration: InputDecoration(
              hintText: 'اختر $label',
              prefixIcon: Icon(_isSale ? PhosphorIconsRegular.user : PhosphorIconsRegular.buildings),
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
            validator: isRequired ? (v) => v == null ? '$label مطلوب للفاتورة الآجلة' : null : null,
          ),
        ],
      ),
    );
  }

  // ── Warehouse section ────────────────────────────────────────
  Widget _buildWarehouseSection() {
    if (_warehouses.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المستودع', style: context.textTheme.titleSmall),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _selectedWarehouseId,
            decoration: const InputDecoration(
              hintText: 'اختر المستودع',
              prefixIcon: Icon(PhosphorIconsRegular.warehouse),
            ),
            items: _warehouses.map((w) => DropdownMenuItem<int>(
              value: w['id'] as int,
              child: Text(w['name'] as String),
            )).toList(),
            onChanged: (val) => setState(() => _selectedWarehouseId = val),
          ),
        ],
      ),
    );
  }

  // ── Items section ────────────────────────────────────────────
  Widget _buildItemsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الأصناف', style: context.textTheme.titleSmall),
              Text('${_items.length} صنف', style: context.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
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
                    Icon(PhosphorIconsRegular.shoppingCart, size: 48, color: AppColors.textHint),
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
                  });
                },
                onDelete: () => setState(() => _items.removeAt(index)),
              );
            }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(PhosphorIconsRegular.plusCircle),
              label: const Text('إضافة صنف'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Transport charges section (optional) ────────────────────
  Widget _buildTransportChargesSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.truck, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('أجور النقل (اختياري)', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _transportChargesController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'أجور النقل',
              prefixIcon: const Icon(PhosphorIconsRegular.truck),
              suffixText: AppConstants.currency,
              hintText: '0.00',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  // ── Summary section ──────────────────────────────────────────
  Widget _buildSummarySection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
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
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (AppConstants.defaultVatRate > 0) ...[
            const SizedBox(height: 8),
            _summaryRow('الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)', CurrencyFormatter.format(_taxAmount)),
          ],
          if (_transportCharges > 0) ...[
            const SizedBox(height: 8),
            _summaryRow('أجور النقل', CurrencyFormatter.format(_transportCharges)),
          ],
          const Divider(height: 24),
          _summaryRow('الإجمالي', CurrencyFormatter.format(_total),
              valueStyle: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
          if (_selectedCurrency != 'YER') ...[
            const SizedBox(height: 4),
            _summaryRow('الإجمالي بالعملة الأساسية', CurrencyFormatter.format(_total * _selectedExchangeRate),
                valueStyle: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المدفوع', style: context.textTheme.bodyMedium),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _paidController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixText: AppConstants.currency,
                    hintText: '0.00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _summaryRow('المتبقي', CurrencyFormatter.format(_remaining),
              valueStyle: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _remaining > 0 ? AppColors.error : AppColors.success,
              )),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظات',
              prefixIcon: Icon(PhosphorIconsRegular.notepad),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {TextStyle? valueStyle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium),
        Text(value, style: valueStyle ?? context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── Bottom action bar ────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: () {},
              icon: const Icon(PhosphorIconsRegular.shareNetwork),
              tooltip: 'مشاركة',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(PhosphorIconsRegular.printer),
                label: const Text('طباعة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveInvoice,
                icon: const Icon(PhosphorIconsRegular.floppyDisk),
                label: const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add item ─────────────────────────────────────────────────
  Future<void> _addItem() async {
    final result = await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddInvoiceItemSheet(warehouseId: _selectedWarehouseId),
    );
    if (result != null) setState(() => _items.add(result));
  }

  // ── Save invoice ─────────────────────────────────────────────
  Future<void> _saveInvoice() async {
    // Validate
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة صنف واحد على الأقل');
      return;
    }
    if (_paymentMechanism == 'credit' && _selectedEntityId == null) {
      context.showErrorSnackBar(_isSale ? 'الرجاء اختيار العميل للفاتورة الآجلة' : 'الرجاء اختيار المورد للفاتورة الآجلة');
      return;
    }
    if (_paymentMechanism == 'cash' && _selectedCashBoxId == null) {
      context.showErrorSnackBar('الرجاء اختيار حساب الصندوق للفاتورة النقدية');
      return;
    }

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
      discountAmount: _discountAmount,
      taxAmount: _taxAmount,
      total: _total,
      paidAmount: _paidAmount,
      remaining: _remaining,
      status: _remaining <= 0 ? 'paid' : _paidAmount > 0 ? 'partial' : 'unpaid',
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
    await db.saveInvoiceWithJournalEntries(
      invoice.toMap(),
      itemsMaps,
      invoiceType: invoice.effectiveType,
      paymentMechanism: _paymentMechanism,
      isReturn: _isReturn,
      cashBoxId: _paymentMechanism == 'cash' ? _selectedCashBoxId : null,
      transportCharges: _transportCharges,
    );

    if (mounted) {
      context.showSuccessSnackBar('تم حفظ الفاتورة بنجاح');
      Navigator.pop(context);
    }
  }
}

/// Card-style payment option for cash/credit selection.
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
          border: Border.all(
            color: isSelected ? color : context.dividerColor,
            width: isSelected ? 2 : 1,
          ),
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
                child: Icon(PhosphorIconsFill.checkCircle, size: 18, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact payment method chip for cash/check/transfer/bank/ewallet/bank_transfer.
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
          border: Border.all(
            color: isSelected ? color : context.dividerColor,
            width: isSelected ? 2 : 1,
          ),
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

