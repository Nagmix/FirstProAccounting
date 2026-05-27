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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            // Actions menu (print, share, bluetooth)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'إجراءات',
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
                const PopupMenuItem(value: 'print', child: ListTile(leading: Icon(Icons.print), title: Text('طباعة PDF'), dense: true)),
                const PopupMenuItem(value: 'bluetooth', child: ListTile(leading: Icon(Icons.bluetooth), title: Text('طباعة حرارية'), dense: true)),
                const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('مشاركة'), dense: true)),
                const PopupMenuItem(value: 'whatsapp', child: ListTile(leading: Icon(Icons.chat, color: Color(0xFF25D366)), title: Text('واتساب'), dense: true)),
              ],
            ),
            // Save button
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ElevatedButton.icon(
                onPressed: _saveInvoice,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('حفظ'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
                      // Row 1: Currency + Return + Payment Mechanism
                      _buildTopRow(),
                      const SizedBox(height: 16),
                      // Account name (unified dropdown)
                      _buildEntitySection(),
                      const SizedBox(height: 16),
                      // Items section
                      _buildItemsSection(),
                      const SizedBox(height: 16),
                      // Summary & Notes
                      _buildSummarySection(),
                      const SizedBox(height: 80), // Bottom padding for scroll
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Partial payment warning ──────────────────────────────────────
  Widget _buildPartialPaymentWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
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

  // ── Top Row: Currency, Return, Payment Mechanism ─────────────────
  Widget _buildTopRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Currency + Return in one row
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _selectedCurrency,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'العملة',
                  prefixIcon: const Icon(Icons.monetization_on, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: _currencies.map((c) => DropdownMenuItem<String>(
                  value: c['code'] as String,
                  child: Text('${c['code']}', style: const TextStyle(fontSize: 13)),
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
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _isReturn = !_isReturn),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    color: _isReturn ? AppColors.error.withValues(alpha: 0.06) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isReturn ? AppColors.error : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.undo, size: 16, color: _isReturn ? AppColors.error : AppColors.textHint),
                      const SizedBox(width: 4),
                      Text('مرتجع', style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isReturn ? AppColors.error : AppColors.textHint,
                      )),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Original invoice selector (only when _isReturn is true)
        if (_isReturn) ...[
          const SizedBox(height: 10),
          _buildOriginalInvoiceSelector(),
        ],
        if (_selectedCurrency != 'YER')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'سعر الصرف: $_selectedExchangeRate',
              style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        const SizedBox(height: 14),
        // Payment mechanism toggle
        Row(
          children: [
            Expanded(
              child: _buildMechanismChip(
                icon: Icons.payments,
                label: 'نقداً',
                isSelected: _paymentMechanism == 'cash',
                color: AppColors.success,
                onTap: () => setState(() => _paymentMechanism = 'cash'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMechanismChip(
                icon: Icons.access_time,
                label: 'أجل',
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
        // Credit info
        if (_paymentMechanism == 'credit') ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.accentOrange, size: 16),
                const SizedBox(width: 6),
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
        // Payment method chips (only when cash)
        if (_paymentMechanism == 'cash') ...[
          const SizedBox(height: 12),
          _buildPaymentMethodRow(),
        ],
        // E-wallet / bank transfer sections
        if (_paymentMechanism == 'cash' && _paymentMethod == 'ewallet')
          _buildEwalletSection(),
        if (_paymentMechanism == 'cash' && _paymentMethod == 'bank_transfer')
          _buildBankTransferSection(),
        // Cash box + paid amount
        if (_paymentMechanism == 'cash') ...[
          const SizedBox(height: 14),
          _buildCashBoxAndPaidRow(),
        ],
      ],
    );
  }

  Widget _buildMechanismChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : AppColors.border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : AppColors.textHint),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 14, color: color),
            ],
          ],
        ),
      ),
    );
  }

  // ── Original Invoice Selector (for returns) ────────────────────────
  Widget _buildOriginalInvoiceSelector() {
    return GestureDetector(
      onTap: _showOriginalInvoiceSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _originalInvoiceId != null
              ? AppColors.error.withValues(alpha: 0.04)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _originalInvoiceId != null
                ? AppColors.error.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.link,
              size: 20,
              color: _originalInvoiceId != null ? AppColors.error : AppColors.textHint,
            ),
            const SizedBox(width: 8),
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
                child: const Icon(Icons.close, size: 18, color: AppColors.textHint),
              )
            else
              const Icon(Icons.arrow_drop_down, size: 20),
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
          title: Row(
            children: [
              const Icon(Icons.link, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('اختر الفاتورة الأصلية', style: context.textTheme.titleMedium),
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
                        const Icon(Icons.receipt_long, size: 48, color: AppColors.textHint),
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
                        selected: isSelected,
                        selectedTileColor: AppColors.primary.withValues(alpha: 0.06),
                        leading: Icon(
                          _isSale ? Icons.receipt : Icons.shopping_cart,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          size: 20,
                        ),
                        title: Text(
                          '# $displayId',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
                        subtitle: Text(
                          '$entityName • ${CurrencyFormatter.format(total)} • $dateStr',
                          style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
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
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Payment method row (compact) ─────────────────────────────────
  Widget _buildPaymentMethodRow() {
    const methods = [
      ('cash', 'نقدي', Icons.payments, AppColors.success),
      ('check', 'شيك', Icons.sticky_note_2, AppColors.accentBlue),
      ('transfer', 'حوالة', Icons.swap_horiz, AppColors.accentOrange),
      ('bank', 'بنك', Icons.account_balance, AppColors.primary),
      ('ewallet', 'محفظة', Icons.account_balance_wallet, AppColors.accentGreen),
      ('bank_transfer', 'حوالة مصرفية', Icons.business, Color(0xFF6A1B9A)),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
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
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? m.$4.withValues(alpha: 0.08) : context.surfaceColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? m.$4 : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(m.$3, size: 14, color: selected ? m.$4 : AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  m.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
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
  Widget _buildEwalletSection() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedEwalletProvider,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'اختر المحفظة الإلكترونية',
              prefixIcon: const Icon(Icons.account_balance_wallet, color: AppColors.accentGreen, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
  Widget _buildBankTransferSection() {
    const purpleColor = Color(0xFF6A1B9A);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: purpleColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: purpleColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedBankTransferProvider,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'اختر شركة الحوالة',
              prefixIcon: const Icon(Icons.business, color: purpleColor, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              prefixIcon: const Icon(Icons.tag, color: purpleColor, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Image.file(File(_attachmentPath!), width: double.infinity, height: 100, fit: BoxFit.cover),
                Positioned(
                  top: 4, left: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _attachmentPath = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.image, size: 16),
                label: Text(isBankTransfer ? 'رفق إشعار' : 'رفق صورة', style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImageFromCamera,
                icon: const Icon(Icons.camera_alt, size: 16),
                label: const Text('تصوير', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Cash box + Paid amount row ───────────────────────────────────
  Widget _buildCashBoxAndPaidRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cash box dropdown
        DropdownButtonFormField<int>(
          value: _selectedCashBoxId,
          isDense: true,
          decoration: InputDecoration(
            labelText: 'الصندوق *',
            prefixIcon: const Icon(Icons.account_balance_wallet, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
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
                  prefixIcon: const Icon(Icons.payments, size: 18),
                  suffixText: _selectedCurrency,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: _autoPay,
                  fillColor: _autoPay ? AppColors.surfaceVariant.withValues(alpha: 0.5) : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            // Auto-pay checkbox
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _autoPay,
                    onChanged: (val) {
                      setState(() {
                        _autoPay = val ?? false;
                        if (_autoPay) {
                          _paidController.text = _total.toStringAsFixed(2);
                        }
                      });
                    },
                    activeColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(height: 2),
                Text('مدفوع', style: context.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: _autoPay ? AppColors.primary : AppColors.textHint,
                  fontWeight: _autoPay ? FontWeight.w700 : FontWeight.w400,
                )),
              ],
            ),
          ],
        ),
        // Remaining amount
        if (!_autoPay && _remaining.abs() > 0.005) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _remaining > 0.005 ? AppColors.error.withValues(alpha: 0.06) : AppColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المتبقي', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
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

  // ── Entity Section (unified dropdown with search) ────────────────
  Widget _buildEntitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Text('اسم الحساب', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (_isEntityRequired) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                child: Text('مطلوب', style: context.textTheme.labelSmall?.copyWith(color: AppColors.error, fontSize: 9)),
              ),
            ] else ...[
              const SizedBox(width: 6),
              Text('(اختياري)', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint, fontSize: 11)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Entity selection field
        GestureDetector(
          onTap: () => setState(() => _showEntityDropdown = !_showEntityDropdown),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _showEntityDropdown ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedEntityType == 'customer' ? Icons.person :
                  _selectedEntityType == 'supplier' ? Icons.business :
                  Icons.person_outline,
                  size: 20,
                  color: _selectedEntityId != null ? AppColors.primary : AppColors.textHint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedEntityName ?? 'اختر حساب...',
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: _selectedEntityId != null ? AppColors.textPrimary : AppColors.textHint,
                    ),
                  ),
                ),
                if (_selectedEntityId != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedEntityId = null;
                      _selectedEntityType = null;
                    }),
                    child: const Icon(Icons.close, size: 18, color: AppColors.textHint),
                  )
                else
                  const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
        // Dropdown with search
        if (_showEntityDropdown) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                // Search field
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _entitySearchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'بحث عن حساب...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: _filterEntities,
                  ),
                ),
                // Add new button
                InkWell(
                  onTap: () => _addNewEntity(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.divider)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.add, size: 16, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isSale ? 'إضافة عميل جديد' : 'إضافة مورد جديد',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Entity list
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 200),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _filteredEntities.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : null,
                          child: Row(
                            children: [
                              Icon(
                                isCustomer ? Icons.person : Icons.business,
                                size: 18,
                                color: isCustomer ? AppColors.success : AppColors.info,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entity['name'] ?? '',
                                  style: context.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (balance != 0)
                                Text(
                                  '${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'}',
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: bt == 'credit' ? AppColors.success : AppColors.error,
                                    fontSize: 10,
                                  ),
                                ),
                              // Type badge
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (isCustomer ? AppColors.success : AppColors.info).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isCustomer ? 'عميل' : 'مورد',
                                  style: context.textTheme.labelSmall?.copyWith(
                                    color: isCustomer ? AppColors.success : AppColors.info,
                                    fontSize: 9,
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
            padding: const EdgeInsets.only(top: 4),
            child: Text('الحساب مطلوب للفاتورة الآجلة', style: context.textTheme.bodySmall?.copyWith(color: AppColors.error, fontSize: 11)),
          ),
      ],
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
  Widget _buildItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('الأصناف', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${_items.length}', style: context.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              )),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, style: BorderStyle.solid),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.textHint),
                  const SizedBox(height: 6),
                  Text('لم يتم إضافة أصناف بعد', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
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
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('إضافة صنف'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Summary Section ──────────────────────────────────────────────
  Widget _buildSummarySection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.summarize, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('الملخص', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal)),
          const SizedBox(height: 6),
          // Discount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الخصم', style: context.textTheme.bodySmall),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _discountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    suffixText: _selectedCurrency,
                    hintText: '0.00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    filled: true,
                    fillColor: AppColors.surfaceVariant.withValues(alpha: 0.3),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) {
                    setState(() {});
                    _updateAutoPay();
                  },
                ),
              ),
            ],
          ),
          if (AppConstants.defaultVatRate > 0) ...[
            const SizedBox(height: 6),
            _summaryRow('الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)', CurrencyFormatter.format(_taxAmount)),
          ],
          // Transport
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('أجور النقل', style: context.textTheme.bodySmall),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _transportChargesController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    suffixText: _selectedCurrency,
                    hintText: '0.00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    filled: true,
                    fillColor: AppColors.surfaceVariant.withValues(alpha: 0.3),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) {
                    setState(() {});
                    _updateAutoPay();
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          _summaryRow('الإجمالي', CurrencyFormatter.format(_total),
              valueStyle: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
          if (_selectedCurrency != 'YER') ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  _summaryRow('المعادل بالريال اليمني', '${CurrencyFormatter.format(_totalInBaseCurrency)} ر.ي',
                      valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.info)),
                  if (_paidAmount > 0.005) ...[
                    const SizedBox(height: 2),
                    _summaryRow('المدفوع (ر.ي)', '${CurrencyFormatter.format(_paidAmountInBaseCurrency)} ر.ي',
                        valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.success)),
                  ],
                  if (_remaining > 0.005) ...[
                    const SizedBox(height: 2),
                    _summaryRow('المتبقي (ر.ي)', '${CurrencyFormatter.format(_remainingInBaseCurrency)} ر.ي',
                        valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.error)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Notes
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'ملاحظات',
              prefixIcon: const Icon(Icons.edit_note, size: 18),
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        Text(label, style: context.textTheme.bodySmall),
        Text(value, style: valueStyle ?? context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: valueColor)),
      ],
    );
  }

  // ── Add item ─────────────────────────────────────────────────────
  Future<void> _addItem() async {
    final result = await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
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
