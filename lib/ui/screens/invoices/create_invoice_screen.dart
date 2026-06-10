import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/license/license_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/viewmodels/invoice_viewmodel.dart';
import '../../../data/datasources/repositories/invoice_repository.dart';
import '../../../data/datasources/services/shift_service.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../settings/bluetooth_printer_settings_screen.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/invoice_model.dart';
import '../customers/add_customer_sheet.dart';
import '../suppliers/add_supplier_sheet.dart';
import 'add_invoice_item_sheet.dart';
import 'widgets/invoice_payment_section.dart';
import 'widgets/invoice_entity_section.dart';
import 'widgets/invoice_items_section.dart';
import 'widgets/invoice_summary_section.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key, required this.invoiceType, this.existingInvoice});

  final String invoiceType;
  final Invoice? existingInvoice;

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _vm = locator<InvoiceViewModel>();
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _discountController = TextEditingController();
  final _paidController = TextEditingController();
  final _transportChargesController = TextEditingController();
  final _transferNumberController = TextEditingController();
  final _entitySearchController = TextEditingController();

  bool get _isSale => _vm.isSale;

  String get _title => _vm.title;

  // Entity is required when: credit mechanism OR (paid < total)
  bool get _isEntityRequired => _vm.isEntityRequired;

  @override
  void initState() {
    super.initState();
    _vm.setInvoiceType(widget.invoiceType);
    _vm.loadData();
    _paidController.text = '0.00';
  }



  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _transportChargesController.dispose();
    _transferNumberController.dispose();
    _entitySearchController.dispose();
    // ViewModel is factory — it will be GC'd with the State.
    super.dispose();
  }

  // Read computed values from ViewModel
  double get _subtotal => _vm.subtotal;
  double get _discountAmount => _vm.discountAmount;
  double get _transportCharges => _vm.transportChargesAmount;
  double get _taxAmount => _vm.taxAmount;
  double get _total => _vm.total;
  double get _paidAmount => _vm.paidAmount;
  double get _remaining => _vm.remaining;
  double get _totalInBaseCurrency => _vm.totalInBaseCurrency;
  double get _paidAmountInBaseCurrency => _vm.paidAmountInBaseCurrency;
  double get _remainingInBaseCurrency => _vm.remainingInBaseCurrency;

  String? get _selectedEntityName => _vm.selectedEntityName;

  /// Sync controller text to ViewModel values and trigger auto-pay update.
  void _syncControllersToVm() {
    _vm.setDiscount(double.tryParse(_discountController.text) ?? 0);
    _vm.setTransportCharges(double.tryParse(_transportChargesController.text) ?? 0);
    _vm.setPaidAmount(double.tryParse(_paidController.text) ?? 0);
    _vm.updateAutoPay();
    // Sync auto-pay paid amount back to controller
    if (_vm.autoPay && _vm.total > 0) {
      _paidController.text = _vm.total.toStringAsFixed(2);
    }
  }

  // ── Image picker helpers ─────────────────────────────────────
  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final savedPath = await _saveImageLocally(picked);
      if (savedPath != null) {
        _vm.setAttachmentPath(savedPath);
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) {
      final savedPath = await _saveImageLocally(picked);
      if (savedPath != null) {
        _vm.setAttachmentPath(savedPath);
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FE),
      appBar: _buildAppBar(isDark),
      body: _vm.isLoading
            ? Center(child: CircularProgressIndicator(color: _accentBlue))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Payment Section (includes partial payment warning when applicable)
                      InvoicePaymentSection(
                        isDark: isDark,
                        paymentMechanism: _vm.paymentMechanism,
                        paymentMethod: _vm.paymentMethod,
                        isReturn: _vm.isReturn,
                        autoPay: _vm.autoPay,
                        selectedCurrency: _vm.selectedCurrency,
                        selectedExchangeRate: _vm.selectedExchangeRate,
                        selectedCashBoxId: _vm.selectedCashBoxId,
                        selectedEwalletProvider: _vm.selectedEwalletProvider,
                        selectedBankTransferProvider: _vm.selectedBankTransferProvider,
                        attachmentPath: _vm.attachmentPath,
                        originalInvoiceId: _vm.originalInvoiceId,
                        originalInvoiceDisplay: _vm.originalInvoiceDisplay,
                        currencies: _vm.currencies,
                        cashBoxes: _vm.cashBoxes,
                        paidController: _paidController,
                        transferNumberController: _transferNumberController,
                        total: _total,
                        paidAmount: _paidAmount,
                        remaining: _remaining,
                        isSale: _isSale,
                        showPartialPaymentWarning: _vm.showPartialPaymentWarning,
                        onToggleReturn: () => _vm.toggleReturn(),
                        onSetCashMechanism: () => _vm.setCashMechanism(),
                        onSetCreditMechanism: () {
                          _vm.setCreditMechanism();
                          _paidController.text = '0';
                        },
                        onPaymentMethodChanged: (method) {
                          _vm.setPaymentMethod(method);
                          if (method == 'bank_transfer') {
                            _transferNumberController.clear();
                          }
                        },
                        onCurrencyChanged: (val) => _vm.setCurrency(val),
                        onCashBoxChanged: (val) => _vm.setCashBox(val),
                        onEwalletProviderChanged: (val) => _vm.setEwalletProvider(val),
                        onBankTransferProviderChanged: (val) => _vm.setBankTransferProvider(val),
                        onPickImageFromGallery: _pickImageFromGallery,
                        onPickImageFromCamera: _pickImageFromCamera,
                        onRemoveAttachment: () => _vm.setAttachmentPath(null),
                        onToggleAutoPay: () {
                          _vm.toggleAutoPay();
                          if (_vm.autoPay) {
                            _paidController.text = _vm.total.toStringAsFixed(2);
                          }
                        },
                        onShowOriginalInvoiceSelector: _showOriginalInvoiceSelector,
                        onClearOriginalInvoice: () => _vm.clearOriginalInvoice(),
                        onPaidChanged: () => _syncControllersToVm(),
                      ),
                      const SizedBox(height: 16),
                      // Entity Section
                      InvoiceEntitySection(
                        isDark: isDark,
                        showEntityDropdown: _vm.showEntityDropdown,
                        selectedEntityId: _vm.selectedEntityId,
                        selectedEntityType: _vm.selectedEntityType,
                        selectedEntityName: _selectedEntityName,
                        filteredEntities: _vm.filteredEntities,
                        entitySearchController: _entitySearchController,
                        isEntityRequired: _isEntityRequired,
                        isSale: _isSale,
                        paymentMechanism: _vm.paymentMechanism,
                        onToggleDropdown: () => _vm.toggleEntityDropdown(),
                        onEntitySelected: (id, type) {
                          _vm.selectEntity(id, type);
                          _entitySearchController.clear();
                        },
                        onClearEntity: () => _vm.clearEntity(),
                        onAddNewEntity: _addNewEntity,
                        onFilterEntities: (query) => _vm.filterEntities(query),
                      ),
                      const SizedBox(height: 16),
                      // Items section
                      InvoiceItemsSection(
                        isDark: isDark,
                        items: _vm.items,
                        onQuantityChanged: (index, qty) {
                          _vm.updateItemQuantity(index, qty);
                          if (_vm.autoPay) {
                            _paidController.text = _vm.total.toStringAsFixed(2);
                          }
                        },
                        onDeleteItem: (index) {
                          _vm.removeItem(index);
                          if (_vm.autoPay) {
                            _paidController.text = _vm.total.toStringAsFixed(2);
                          }
                        },
                        onAddItem: _addItem,
                      ),
                      const SizedBox(height: 16),
                      // Summary & Notes
                      InvoiceSummarySection(
                        isDark: isDark,
                        subtotal: _subtotal,
                        discountAmount: _discountAmount,
                        taxAmount: _taxAmount,
                        transportCharges: _transportCharges,
                        total: _total,
                        paidAmount: _paidAmount,
                        remaining: _remaining,
                        totalInBaseCurrency: _totalInBaseCurrency,
                        paidAmountInBaseCurrency: _paidAmountInBaseCurrency,
                        remainingInBaseCurrency: _remainingInBaseCurrency,
                        selectedCurrency: _vm.selectedCurrency,
                        discountController: _discountController,
                        transportChargesController: _transportChargesController,
                        notesController: _notesController,
                        onDiscountChanged: () => _syncControllersToVm(),
                        onTransportChanged: () => _syncControllersToVm(),
                      ),
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
          tooltip: 'رجوع',
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
          if (_vm.isReturn) ...[
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

  // ── Original invoice selector dialog ─────────────────────────────
  void _showOriginalInvoiceSelector() async {
    // Get recent non-return invoices of the same type (sale or purchase)
    final invoices = await locator<InvoiceRepository>().getInvoicesByType(widget.invoiceType);

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
                      final total = MoneyHelper.readMoney(inv['total']);
                      final createdAt = DateTime.tryParse(inv['created_at'] as String? ?? '');
                      final dateStr = createdAt != null ? DateFormatter.formatDateTime(createdAt) : '';
                      final displayId = invId.length > 12 ? '...${invId.substring(invId.length - 8)}' : invId;
                      final isSelected = _vm.originalInvoiceId != null && invId == _vm.originalInvoiceId;

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
                          _vm.setOriginalInvoice(invId, '# $displayId • $entityName • ${CurrencyFormatter.format(total)}');
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

  // ── Add new entity ───────────────────────────────────────────────
  Future<void> _addNewEntity() async {
    _vm.setShowEntityDropdown(false);
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

    if (!mounted) return;

    // Reload entities after adding
    await _vm.reloadEntities();
  }

  // ── Add item ─────────────────────────────────────────────────────
  Future<void> _addItem() async {
    final result = await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddInvoiceItemSheet(warehouseId: _vm.selectedWarehouseId, invoiceType: widget.invoiceType),
    );
    if (result != null) {
      _vm.addItem(result);
      if (_vm.autoPay) {
        _paidController.text = _vm.total.toStringAsFixed(2);
      }
    }
  }

  // ── Record limit check ──────────────────────────────────────────

  Future<bool> _checkRecordLimit() async {
    final canAdd = await context.read<LicenseProvider>().canAddRecord();
    if (!canAdd && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تم تجاوز الحد الأقصى'),
          content: const Text(
            'لقد وصلت إلى الحد الأقصى للسجلات في النسخة المجانية (500 سجل). '
            'قم بتفعيل الترخيص لإضافة سجلات غير محدودة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/license-activation');
              },
              child: const Text('تفعيل الترخيص'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  // ── Save invoice ─────────────────────────────────────────────────
  Future<void> _saveInvoice() async {
    // Sync controllers to VM before validation
    _syncControllersToVm();

    // Check record limit
    final canAdd = await _checkRecordLimit();
    if (!canAdd || !mounted) return;

    // Validate
    if (_vm.items.isEmpty) {
      if (!mounted) return;
      context.showErrorSnackBar('الرجاء إضافة صنف واحد على الأقل');
      return;
    }
    if (_vm.isEntityRequired && _vm.selectedEntityId == null) {
      context.showErrorSnackBar('الحساب مطلوب');
      return;
    }
    if (_vm.paymentMechanism == 'cash' && _vm.selectedCashBoxId == null) {
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
    if (_vm.isReturn && _vm.originalInvoiceId == null) {
      context.showErrorSnackBar('يجب ربط الفاتورة المرتجعة بالفاتورة الأصلية');
      return;
    }

    // Check return limits if this is a return invoice with an original invoice linked
    if (_vm.isReturn && _vm.originalInvoiceId != null) {
      final itemsMaps = _vm.items.map((item) => <String, dynamic>{
        'product_id': item.productId,
        'product_name': item.productName,
        'quantity': item.quantity,
        'base_quantity': item.baseQuantity,
        'unit_price': item.unitPrice,
        'total_price': item.totalPrice,
      }).toList();
      final limitErrors = await locator<InvoiceRepository>().checkReturnLimits(_vm.originalInvoiceId!, itemsMaps);
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
    final effectivePaymentMechanism = _vm.paymentMechanism;
    final effectivePaidAmount = _vm.paymentMechanism == 'credit' ? 0.0 : _paidAmount;

    final invoiceId = const Uuid().v4();
    final invoice = Invoice(
      id: invoiceId,
      type: widget.invoiceType,
      paymentMechanism: _vm.paymentMechanism,
      paymentMethod: _vm.paymentMethod,
      isReturn: _vm.isReturn,
      cashBoxId: _vm.paymentMechanism == 'cash' ? _vm.selectedCashBoxId : null,
      customerId: _vm.selectedEntityType == 'customer' ? _vm.selectedEntityId : null,
      supplierId: _vm.selectedEntityType == 'supplier' ? _vm.selectedEntityId : null,
      subtotal: _subtotal,
      discountRate: _subtotal > 0 ? (_discountAmount / _subtotal) * 100 : 0.0,
      discountAmount: _discountAmount,
      taxAmount: _taxAmount,
      total: _total,
      paidAmount: _paidAmount,
      remaining: _remaining,
      status: _remaining <= 0.005 ? 'paid' : _paidAmount > 0.005 ? 'partial' : 'unpaid',
      warehouseId: _vm.selectedWarehouseId,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      currency: _vm.selectedCurrency,
      exchangeRate: _vm.selectedExchangeRate,
      ewalletProvider: _vm.paymentMethod == 'ewallet' ? _vm.selectedEwalletProvider : null,
      bankTransferProvider: _vm.paymentMethod == 'bank_transfer' ? _vm.selectedBankTransferProvider : null,
      transferNumber: _vm.paymentMethod == 'bank_transfer' && _transferNumberController.text.isNotEmpty
          ? _transferNumberController.text
          : null,
      attachmentPath: (_vm.paymentMethod == 'ewallet' || _vm.paymentMethod == 'bank_transfer')
          ? _vm.attachmentPath
          : null,
      originalInvoiceId: _vm.isReturn ? _vm.originalInvoiceId : null,
    );

    final itemsMaps = _vm.items.map((item) => {
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

    await locator<InvoiceRepository>().saveInvoiceWithJournalEntries(
      invoice.toMap(),
      itemsMaps,
      invoiceType: invoice.effectiveType,
      paymentMechanism: effectivePaymentMechanism,
      isReturn: _vm.isReturn,
      cashBoxId: _vm.paymentMechanism == 'cash' ? _vm.selectedCashBoxId : null,
      transportChargesParam: _transportCharges,
      paidAmount: effectivePaidAmount,
    );

    // Update shift totals if this is a return invoice and a shift is active
    if (_vm.isReturn && _vm.selectedCashBoxId != null) {
      try {
        final activeShift = await locator<ShiftService>().getActiveShift(_vm.selectedCashBoxId!);
        if (activeShift != null) {
          final shiftId = activeShift['id'] as int;
          await locator<ShiftService>().updateShiftTotals(shiftId, 0.0, _total, 0.0);
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
    if (_vm.items.isEmpty) {
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
    for (final item in _vm.items) {
      buffer.writeln('  ${item.productName} × ${item.quantity} = ${CurrencyFormatter.format(item.totalPrice)}');
    }
    if (_notesController.text.isNotEmpty) buffer.writeln('ملاحظات: ${_notesController.text}');
    Share.share(buffer.toString(), subject: _title);
  }

  // ── Share via WhatsApp ───────────────────────────────────────────
  void _shareInvoiceWhatsApp() {
    if (_vm.items.isEmpty) {
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
    for (final item in _vm.items) {
      buffer.writeln('▫️ ${item.productName} × ${item.quantity} = ${CurrencyFormatter.format(item.totalPrice)}');
    }
    if (_notesController.text.isNotEmpty) buffer.writeln('ملاحظات: ${_notesController.text}');
    Share.share(buffer.toString(), subject: _title);
  }

  // ── Print invoice ────────────────────────────────────────────────
  Future<void> _printInvoice() async {
    if (_vm.items.isEmpty) {
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
        'customer_id': _vm.selectedEntityId,
        'subtotal': _subtotal,
        'discount_amount': _discountAmount,
        'tax_amount': _taxAmount,
        'transport_charges': _transportCharges,
        'total': _total,
        'paid_amount': _paidAmount,
        'remaining': _remaining,
        'status': _remaining <= 0 ? 'paid' : 'unpaid',
        'payment_method': _vm.paymentMethod,
        'currency': _vm.selectedCurrency,
        'notes': _notesController.text,
        'entity_name': entityName,
        'created_at': DateTime.now().toIso8601String(),
      };

      final itemsMap = _vm.items.map((item) => <String, dynamic>{
        'product_name': item.productName,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total_price': item.totalPrice,
        'unit_name': item.unitName,
        'base_quantity': item.baseQuantity,
      }).toList();

      await InvoicePdfGenerator.printInvoice(invoiceMap, itemsMap);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('حدث خطأ أثناء الطباعة');
    }
  }

  /// Print via Bluetooth thermal printer.
  Future<void> _printBluetooth() async {
    if (_vm.items.isEmpty) {
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
      final currencySymbol = _vm.selectedCurrency == 'SAR' ? 'ر.س' : _vm.selectedCurrency == 'USD' ? r'$' : 'ر.ي';

      await printerService.printReceipt({
        'invoice_number': '—',
        'invoice_type': _isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات',
        'date': DateTime.now(),
        'customer_name': entityName,
        'items': _vm.items.map((item) => <String, dynamic>{
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
      if (mounted) context.showErrorSnackBar('حدث خطأ أثناء الطباعة الحرارية');
    }
  }
}
