import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/invoice_model.dart';
import '../../widgets/invoice_item_card.dart';
import 'add_invoice_item_sheet.dart';

/// Full invoice creation / editing screen.
///
/// Supports both sale and purchase invoice types. All text is Arabic
/// and the layout is fully RTL with Material 3 design.
class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({
    super.key,
    required this.invoiceType,
    this.existingInvoice,
  });

  final String invoiceType;
  final Invoice? existingInvoice;

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  // ── Form state ───────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _discountController = TextEditingController();
  final _paidController = TextEditingController();

  String _paymentMethod = 'cash'; // cash, credit, bank, check, card
  int? _selectedCustomerId;
  final List<InvoiceItem> _items = [];

  // ── Demo customers ───────────────────────────────────────────────
  final List<Map<String, dynamic>> _customers = const [
    {'id': 1, 'name': 'أحمد محمد العلي'},
    {'id': 2, 'name': 'شركة النور للتجارة'},
    {'id': 3, 'name': 'مؤسسة الفجر'},
    {'id': 4, 'name': 'عبدالله الخالدي'},
    {'id': 5, 'name': 'محمد السعيد'},
  ];

  // ── Demo suppliers (for purchase invoices) ───────────────────────
  final List<Map<String, dynamic>> _suppliers = const [
    {'id': 1, 'name': 'مورد المواد الخام'},
    {'id': 2, 'name': 'شركة التوريدات المتحدة'},
    {'id': 3, 'name': 'مؤسسة الجودة'},
  ];

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  // ── Computed properties ──────────────────────────────────────────
  double get _subtotal =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get _discountAmount {
    final val = double.tryParse(_discountController.text) ?? 0;
    return val;
  }

  double get _taxAmount =>
      (_subtotal - _discountAmount) * (AppConstants.defaultVatRate / 100);

  double get _total => _subtotal - _discountAmount + _taxAmount;

  double get _paidAmount => double.tryParse(_paidController.text) ?? 0;

  double get _remaining => _total - _paidAmount;

  String get _title {
    if (widget.invoiceType == AppConstants.saleInvoice) {
      return 'فاتورة بيع جديدة';
    }
    if (widget.invoiceType == AppConstants.purchaseInvoice) {
      return 'فاتورة شراء جديدة';
    }
    return 'فاتورة جديدة';
  }

  bool get _isSale =>
      widget.invoiceType == AppConstants.saleInvoice ||
      widget.invoiceType == AppConstants.returnInvoice;

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
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
              icon: const Icon(Icons.save_outlined),
              tooltip: 'حفظ',
            ),
            IconButton(
              onPressed: () {
                // TODO: more options
              },
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCustomerSection(),
                      _buildPaymentMethodSection(),
                      _buildItemsSection(),
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

  // ── Customer section ─────────────────────────────────────────────
  Widget _buildCustomerSection() {
    final entities = _isSale ? _customers : _suppliers;
    final label = _isSale ? 'العميل' : 'المورد';

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
          Text(label, style: context.textTheme.titleSmall),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _selectedCustomerId,
            decoration: InputDecoration(
              hintText: 'اختر $label',
              prefixIcon: Icon(
                _isSale ? Icons.person_outline : Icons.business_outlined,
              ),
            ),
            items: entities.map((e) {
              return DropdownMenuItem<int>(
                value: e['id'] as int,
                child: Text(e['name'] as String),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedCustomerId = val;
              });
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                // TODO: navigate to add customer
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                _isSale ? 'إضافة عميل جديد' : 'إضافة مورد جديد',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment method section ───────────────────────────────────────
  Widget _buildPaymentMethodSection() {
    const methods = [
      ('cash', 'نقد', Icons.money),
      ('credit', 'أجل', Icons.schedule),
      ('bank', 'بنك', Icons.account_balance),
      ('check', 'شيك', Icons.description_outlined),
      ('card', 'كاش', Icons.credit_card),
    ];

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
          Text('طريقة الدفع', style: context.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: methods.map((m) {
              final selected = _paymentMethod == m.$1;
              return ChoiceChip(
                avatar: Icon(m.$3, size: 18),
                label: Text(m.$2),
                selected: selected,
                onSelected: (_) => setState(() => _paymentMethod = m.$1),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Items section ────────────────────────────────────────────────
  Widget _buildItemsSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الأصناف', style: context.textTheme.titleSmall),
              Text(
                '${_items.length} صنف',
                style: context.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // List of items
          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.dividerColor,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.add_shopping_cart_outlined,
                        size: 48, color: AppColors.textHint),
                    const SizedBox(height: 8),
                    Text('لم يتم إضافة أصناف بعد',
                        style: context.textTheme.bodyMedium),
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
                    _items[index] = item.copyWith(
                      quantity: qty,
                      totalPrice: qty * item.unitPrice,
                    );
                  });
                },
                onDelete: () {
                  setState(() => _items.removeAt(index));
                },
              );
            }),

          const SizedBox(height: 8),

          // Add item button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('إضافة صنف'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary section ──────────────────────────────────────────────
  Widget _buildSummarySection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    suffixText: AppConstants.currency,
                    hintText: '0.00',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)',
            CurrencyFormatter.format(_taxAmount),
          ),
          const Divider(height: 24),
          _summaryRow(
            'الإجمالي',
            CurrencyFormatter.format(_total),
            valueStyle: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    suffixText: AppConstants.currency,
                    hintText: '0.00',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'المتبقي',
            CurrencyFormatter.format(_remaining),
            valueStyle: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _remaining > 0 ? AppColors.error : AppColors.success,
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
        Text(value,
            style: valueStyle ??
                context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
      ],
    );
  }

  // ── Bottom action bar ────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Share
            IconButton.outlined(
              onPressed: () {
                // TODO: share invoice
              },
              icon: const Icon(Icons.share),
              tooltip: 'مشاركة',
            ),
            const SizedBox(width: 8),

            // Print
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: print invoice
                },
                icon: const Icon(Icons.print),
                label: const Text('طباعة'),
              ),
            ),
            const SizedBox(width: 8),

            // Save
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
      builder: (_) => const AddInvoiceItemSheet(),
    );

    if (result != null) {
      setState(() => _items.add(result));
    }
  }

  // ── Save invoice ─────────────────────────────────────────────────
  void _saveInvoice() {
    if (_items.isEmpty) {
      context.showErrorSnackBar('الرجاء إضافة صنف واحد على الأقل');
      return;
    }
    if (_selectedCustomerId == null) {
      context.showErrorSnackBar('الرجاء اختيار العميل');
      return;
    }

    final invoice = Invoice(
      id: const Uuid().v4(),
      type: widget.invoiceType,
      paymentType: _paymentMethod,
      customerId: _isSale ? _selectedCustomerId : null,
      supplierId: !_isSale ? _selectedCustomerId : null,
      subtotal: _subtotal,
      discountAmount: _discountAmount,
      taxAmount: _taxAmount,
      total: _total,
      paidAmount: _paidAmount,
      remaining: _remaining,
      status: _remaining <= 0
          ? 'paid'
          : _paidAmount > 0
              ? 'partial'
              : 'unpaid',
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    // TODO: persist invoice via provider / database
    debugPrint('Invoice saved: ${invoice.toMap()}');

    context.showSuccessSnackBar('تم حفظ الفاتورة بنجاح');
    Navigator.pop(context);
  }
}
