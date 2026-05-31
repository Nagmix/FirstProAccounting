import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../core/utils/money_helper.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../data/datasources/repositories/invoice_repository.dart';
import '../../../../data/datasources/repositories/customer_repository.dart';
import '../../../../data/datasources/repositories/supplier_repository.dart';
import '../../../../data/datasources/services/cash_box_service.dart';
import '../../../../data/datasources/services/audit_service.dart';
import '../../../data/models/invoice_item_model.dart';

/// Invoice detail screen – shows comprehensive info about a single invoice.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _items = [];
  String _entityName = '—';
  double _entityBalance = 0.0;
  String _entityBalanceType = 'credit';
  String _cashBoxName = '—';
  bool _isLoading = true;

  // Linked invoice data
  Map<String, dynamic>? _originalInvoice;
  List<Map<String, dynamic>> _linkedReturns = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final invoice = await locator<InvoiceRepository>().getInvoiceById(widget.invoiceId);
    if (invoice == null) {
      setState(() => _isLoading = false);
      return;
    }

    final items = await locator<InvoiceRepository>().getInvoiceItems(widget.invoiceId);

    // Load entity name and balance
    String entityName = '—';
    double entityBalance = 0.0;
    String entityBalanceType = 'credit';

    if (invoice['customer_id'] != null) {
      final customers = await locator<CustomerRepository>().getAllCustomers();
      final customer = customers.where((c) => c['id'] == invoice['customer_id']).firstOrNull;
      if (customer != null) {
        entityName = customer['name'] as String? ?? '—';
        entityBalance = MoneyHelper.readMoney(customer['balance']);
        entityBalanceType = customer['balance_type'] as String? ?? 'credit';
      }
    } else if (invoice['supplier_id'] != null) {
      final suppliers = await locator<SupplierRepository>().getAllSuppliers();
      final supplier = suppliers.where((s) => s['id'] == invoice['supplier_id']).firstOrNull;
      if (supplier != null) {
        entityName = supplier['name'] as String? ?? '—';
        entityBalance = MoneyHelper.readMoney(supplier['balance']);
        entityBalanceType = supplier['balance_type'] as String? ?? 'credit';
      }
    }

    // Load cash box name
    String cashBoxName = '—';
    if (invoice['cash_box_id'] != null) {
      final cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
      final cashBox = cashBoxes.where((cb) => cb['id'] == invoice['cash_box_id']).firstOrNull;
      if (cashBox != null) {
        cashBoxName = cashBox['name'] as String? ?? '—';
      }
    }

    // Load linked original invoice
    Map<String, dynamic>? originalInvoice;
    final originalInvoiceId = invoice['original_invoice_id'] as String?;
    if (originalInvoiceId != null && originalInvoiceId.isNotEmpty) {
      originalInvoice = await locator<InvoiceRepository>().getInvoiceById(originalInvoiceId);
    }

    // Load linked return invoices
    List<Map<String, dynamic>> linkedReturns = [];
    linkedReturns = await locator<InvoiceRepository>().getLinkedReturns(widget.invoiceId);

    setState(() {
      _invoice = invoice;
      _items = items;
      _entityName = entityName;
      _entityBalance = entityBalance;
      _entityBalanceType = entityBalanceType;
      _cashBoxName = cashBoxName;
      _originalInvoice = originalInvoice;
      _linkedReturns = linkedReturns;
      _isLoading = false;
    });
  }

  bool get _isSale {
    final type = _invoice?['type'] as String? ?? '';
    return type == 'sale' || type == 'sale_return';
  }

  String get _invoiceTypeAr {
    final type = _invoice?['type'] as String? ?? '';
    final isReturn = (_invoice?['is_return'] as int?) == 1;
    return switch (type) {
      'sale' => isReturn ? 'فاتورة مرتجع مبيعات' : 'فاتورة مبيعات',
      'purchase' => isReturn ? 'فاتورة مرتجع مشتريات' : 'فاتورة مشتريات',
      'pos' => 'فاتورة نقطة بيع',
      'sale_return' => 'فاتورة مرتجع مبيعات',
      'purchase_return' => 'فاتورة مرتجع مشتريات',
      _ => 'فاتورة',
    };
  }

  String _displayInvoiceId(String? id) {
    if (id == null || id.isEmpty) return '—';
    if (id.length > 12) return '...${id.substring(id.length - 8)}';
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل الفاتورة'),
          actions: [
            IconButton(
              onPressed: _shareInvoice,
              icon: const Icon(Icons.share),
              tooltip: 'مشاركة',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _invoice == null
                ? _buildNotFoundError()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderSection(),
                          if (_originalInvoice != null)
                            _buildOriginalInvoiceSection(),
                          if (_linkedReturns.isNotEmpty)
                            _buildLinkedReturnsSection(),
                          _buildEntitySection(),
                          _buildPaymentInfoSection(),
                          _buildItemsTable(),
                          _buildSummarySection(),
                          if ((_invoice?['notes'] as String?)?.isNotEmpty == true)
                            _buildNotesSection(),
                        ],
                      ),
                    ),
                  ),
        bottomNavigationBar: _invoice != null ? _buildBottomActions() : null,
      ),
    );
  }

  // ── Header section ───────────────────────────────────────────────
  Widget _buildHeaderSection() {
    final type = _invoice?['type'] as String? ?? '';
    final isReturn = (_invoice?['is_return'] as int?) == 1;
    final status = _invoice?['status'] as String? ?? 'pending';
    final createdAt = DateTime.tryParse(_invoice?['created_at'] as String? ?? '') ?? DateTime.now();
    final remaining = MoneyHelper.readMoney(_invoice?['remaining']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _isSale
            ? LinearGradient(colors: [AppColors.primary, AppColors.primaryLight], begin: Alignment.topRight, end: Alignment.bottomLeft)
            : LinearGradient(colors: [AppColors.accentOrange, const Color(0xFFFF8F00)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isReturn ? Icons.refresh : (_isSale ? Icons.receipt : Icons.shopping_cart),
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _invoiceTypeAr,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _buildStatusChip(status),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '# ${_displayInvoiceId(_invoice?['id'] as String?)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                DateFormatter.formatDateTime(createdAt),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              if (remaining > 0.005) ...[
                Icon(Icons.pending, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  'المتبقي: ${CurrencyFormatter.format(remaining)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final (label, bgColor, fgColor) = switch (status) {
      'paid' => ('مدفوع', AppColors.success, Colors.white),
      'unpaid' => ('غير مدفوع', AppColors.error, Colors.white),
      'partial' => ('مدفوع جزئياً', AppColors.info, Colors.white),
      'pending' => ('معلق', AppColors.warning, Colors.white),
      'cancelled' => ('ملغي', AppColors.textSecondary, Colors.white),
      _ => (status, AppColors.textSecondary, Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fgColor)),
    );
  }

  // ── Original invoice link section ────────────────────────────────
  Widget _buildOriginalInvoiceSection() {
    final originalId = _originalInvoice?['id'] as String? ?? '';
    final originalType = _originalInvoice?['type'] as String? ?? '';
    final originalTotal = MoneyHelper.readMoney(_originalInvoice?['total']);
    final originalDate = DateTime.tryParse(_originalInvoice?['created_at'] as String? ?? '');
    final dateStr = originalDate != null ? DateFormatter.formatDateTime(originalDate) : '';
    final displayId = originalId.length > 12 ? '...${originalId.substring(originalId.length - 8)}' : originalId;
    final typeAr = originalType == 'sale' ? 'مبيعات' : originalType == 'purchase' ? 'مشتريات' : originalType;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, size: 20, color: AppColors.info),
              const SizedBox(width: 8),
              Text('فاتورة مرتبطة', style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.info,
              )),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceDetailScreen(invoiceId: originalId),
                ),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.info.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt, size: 20, color: AppColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'فاتورة $typeAr - # $displayId',
                          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${CurrencyFormatter.format(originalTotal)} • $dateStr',
                          style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.info),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Linked returns section ───────────────────────────────────────
  Widget _buildLinkedReturnsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.undo, size: 20, color: AppColors.error),
              const SizedBox(width: 8),
              Text('فواتير المرتجع المرتبطة', style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_linkedReturns.length}',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._linkedReturns.map((ret) {
            final retId = ret['id'] as String? ?? '';
            final entityName = ret['entity_name'] as String? ?? '—';
            final total = MoneyHelper.readMoney(ret['total']);
            final status = ret['status'] as String? ?? '';
            final createdAt = DateTime.tryParse(ret['created_at'] as String? ?? '');
            final dateStr = createdAt != null ? DateFormatter.formatDateTime(createdAt) : '';
            final displayId = retId.length > 12 ? '...${retId.substring(retId.length - 8)}' : retId;
            final isCancelled = status == 'cancelled';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailScreen(invoiceId: retId),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCancelled
                          ? AppColors.textHint.withOpacity(0.3)
                          : AppColors.error.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 18,
                        color: isCancelled ? AppColors.textHint : AppColors.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '# $displayId',
                              style: context.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: isCancelled ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$entityName • ${CurrencyFormatter.format(total)} • $dateStr${isCancelled ? ' • ملغاة' : ''}',
                              style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Entity section ───────────────────────────────────────────────
  Widget _buildEntitySection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
              Icon(_isSale ? Icons.person : Icons.business, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                _isSale ? 'العميل' : 'المورد',
                style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _entityName,
                  style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (_entityBalance != 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _entityBalance > 0 ? AppColors.successLight : AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${CurrencyFormatter.format(_entityBalance.abs())} ${_entityBalance > 0 ? "له" : "عليه"}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _entityBalance > 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Payment info section ─────────────────────────────────────────
  Widget _buildPaymentInfoSection() {
    final paymentMechanism = _invoice?['payment_mechanism'] as String? ?? 'cash';
    final paymentMethod = _invoice?['payment_method'] as String? ?? 'cash';
    final currency = _invoice?['currency'] as String? ?? 'YER';

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
              const Icon(Icons.account_balance_wallet, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('معلومات الدفع', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('آلية الدفع', paymentMechanism == 'cash' ? 'نقداً' : 'آجل'),
          const SizedBox(height: 8),
          _infoRow('طريقة الدفع', _paymentMethodAr(paymentMethod)),
          const SizedBox(height: 8),
          _infoRow('الصندوق', _cashBoxName),
          const SizedBox(height: 8),
          _infoRow('العملة', currency),
        ],
      ),
    );
  }

  String _paymentMethodAr(String method) {
    return switch (method) {
      'cash' => 'نقدي',
      'check' => 'شيك',
      'transfer' => 'حوالة',
      'bank' => 'بنك',
      'ewallet' => 'محفظة إلكترونية',
      'bank_transfer' => 'حوالة مصرفية',
      _ => method,
    };
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── Items table ──────────────────────────────────────────────────
  Widget _buildItemsTable() {
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
              const Icon(Icons.inventory_2, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('الأصناف', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${_items.length} صنف', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('الصنف', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
                Expanded(flex: 1, child: Text('الكمية', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('سعر الوحدة', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('الإجمالي', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ..._items.map((item) {
            final itemModel = InvoiceItem.fromMap(item);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(itemModel.productName, style: context.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 1, child: Text(itemModel.quantity.toStringAsFixed(itemModel.quantity == itemModel.quantity.truncateToDouble() ? 0 : 2), style: context.textTheme.bodyMedium, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text(CurrencyFormatter.format(itemModel.unitPrice), style: context.textTheme.bodyMedium, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text(CurrencyFormatter.format(itemModel.totalPrice), style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Summary section ──────────────────────────────────────────────
  Widget _buildSummarySection() {
    final subtotal = MoneyHelper.readMoney(_invoice?['subtotal']);
    final discountAmount = MoneyHelper.readMoney(_invoice?['discount_amount']);
    final taxAmount = MoneyHelper.readMoney(_invoice?['tax_amount']);
    final transportCharges = MoneyHelper.readMoney(_invoice?['transport_charges']);
    final total = MoneyHelper.readMoney(_invoice?['total']);
    final paidAmount = MoneyHelper.readMoney(_invoice?['paid_amount']);
    final remaining = MoneyHelper.readMoney(_invoice?['remaining']);

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
          _summaryRow('المجموع الفرعي', CurrencyFormatter.format(subtotal)),
          if (discountAmount > 0) ...[
            const SizedBox(height: 8),
            _summaryRow('الخصم', CurrencyFormatter.format(discountAmount), valueColor: AppColors.error),
          ],
          if (taxAmount > 0) ...[
            const SizedBox(height: 8),
            _summaryRow('الضريبة', CurrencyFormatter.format(taxAmount)),
          ],
          if (transportCharges > 0) ...[
            const SizedBox(height: 8),
            _summaryRow('أجور النقل', CurrencyFormatter.format(transportCharges)),
          ],
          const Divider(height: 24),
          _summaryRow('الإجمالي', CurrencyFormatter.format(total),
              valueStyle: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: _isSale ? AppColors.primary : AppColors.accentOrange)),
          const SizedBox(height: 8),
          _summaryRow('المدفوع', CurrencyFormatter.format(paidAmount), valueColor: AppColors.success),
          const SizedBox(height: 8),
          _summaryRow('المتبقي', CurrencyFormatter.format(remaining),
              valueColor: remaining > 0.005 ? AppColors.error : AppColors.success),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {TextStyle? valueStyle, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium),
        Text(
          value,
          style: valueStyle ?? context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ── Notes section ────────────────────────────────────────────────
  Widget _buildNotesSection() {
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
              const Icon(Icons.edit_note, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('ملاحظات', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _invoice?['notes'] as String? ?? '',
            style: context.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // ── Error state ──────────────────────────────────────────────────
  Widget _buildNotFoundError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('لم يتم العثور على الفاتورة', style: context.textTheme.titleMedium),
        ],
      ),
    );
  }

  // ── Bottom actions ───────────────────────────────────────────────
  Widget _buildBottomActions() {
    final remaining = MoneyHelper.readMoney(_invoice?['remaining']);
    final status = _invoice?['status'] as String? ?? 'pending';
    final isCancelled = status == 'cancelled';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCancelled)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _confirmCancelInvoice,
                  icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
                  label: const Text('إلغاء الفاتورة', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            if (!isCancelled) const SizedBox(height: 8),
            if (remaining > 0.005 && !isCancelled)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showRecordPaymentDialog,
                  icon: const Icon(Icons.payment),
                  label: const Text('تسجيل دفعة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: _isSale ? AppColors.primary : AppColors.accentOrange),
                  ),
                ),
              ),
            if (remaining > 0.005 && !isCancelled) const SizedBox(height: 8),
            Row(
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
                  child: ElevatedButton.icon(
                    onPressed: _printInvoice,
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Record Payment Dialog ────────────────────────────────────────
  void _showRecordPaymentDialog() {
    final remaining = MoneyHelper.readMoney(_invoice?['remaining']);
    final amountController = TextEditingController(text: remaining.toStringAsFixed(2));
    int? selectedCashBoxId;
    List<Map<String, dynamic>> cashBoxes = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16, right: 16, top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text('تسجيل دفعة', style: context.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('المتبقي: ${CurrencyFormatter.format(remaining)}', style: context.textTheme.bodyMedium?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'مبلغ الدفعة',
                        prefixIcon: const Icon(Icons.payments),
                        suffixText: AppConstants.currency,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: locator<CashBoxService>().getAllCashBoxes(),
                      builder: (ctx, snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();
                        cashBoxes = snapshot.data!;
                        return DropdownButtonFormField<int>(
                          value: selectedCashBoxId,
                          decoration: InputDecoration(
                            labelText: 'اختر الصندوق',
                            prefixIcon: const Icon(Icons.account_balance_wallet),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: cashBoxes.map((cb) => DropdownMenuItem<int>(
                            value: cb['id'] as int,
                            child: Text(cb['name'] as String),
                          )).toList(),
                          onChanged: (val) => setModalState(() => selectedCashBoxId = val),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          final amount = double.tryParse(amountController.text) ?? 0;
                          if (amount <= 0) {
                            context.showErrorSnackBar('أدخل مبلغ صحيح');
                            return;
                          }
                          if (selectedCashBoxId == null) {
                            context.showErrorSnackBar('اختر الصندوق');
                            return;
                          }
                          Navigator.pop(ctx);
                          await locator<InvoiceRepository>().recordInvoicePayment(
                            invoiceId: widget.invoiceId,
                            amount: amount,
                            cashBoxId: selectedCashBoxId!,
                          );
                          if (mounted) {
                            context.showSuccessSnackBar('تم تسجيل الدفعة بنجاح');
                            _loadData();
                          }
                        },
                        child: const Text('تسجيل الدفعة'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Cancel Invoice ───────────────────────────────────────────────
  void _confirmCancelInvoice() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Text('تأكيد إلغاء الفاتورة'),
            ],
          ),
          content: const Text(
            'هل أنت متأكد من إلغاء هذه الفاتورة؟ سيتم عكس جميع القيود المحاسبية المرتبطة بها ولا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تراجع'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _cancelInvoice();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('إلغاء الفاتورة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelInvoice() async {
    try {
      await locator<InvoiceRepository>().cancelInvoice(widget.invoiceId);
      // Log audit event from the UI side as well for extra traceability
      await locator<AuditService>().logAuditEvent(
        action: 'cancel',
        tableName: 'invoices',
        recordId: int.tryParse(widget.invoiceId),
        recordType: _invoice?['type'] as String?,
        oldValues: jsonEncode({'status': _invoice?['status'], 'invoiceId': widget.invoiceId}),
        newValues: jsonEncode({'status': 'cancelled', 'invoiceId': widget.invoiceId}),
      );
      if (mounted) {
        context.showSuccessSnackBar('تم إلغاء الفاتورة بنجاح');
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // ── Share & Print ────────────────────────────────────────────────
  void _shareInvoice() {
    if (_invoice == null) return;
    final buffer = StringBuffer();
    buffer.writeln(_invoiceTypeAr);
    buffer.writeln('──────────────────');
    buffer.writeln('رقم: ${_displayInvoiceId(_invoice?['id'] as String?)}');
    buffer.writeln('${_isSale ? 'العميل' : 'المورد'}: $_entityName');
    buffer.writeln('الإجمالي: ${CurrencyFormatter.format(MoneyHelper.readMoney(_invoice?['total']))}');
    buffer.writeln('المدفوع: ${CurrencyFormatter.format(MoneyHelper.readMoney(_invoice?['paid_amount']))}');
    buffer.writeln('المتبقي: ${CurrencyFormatter.format(MoneyHelper.readMoney(_invoice?['remaining']))}');
    buffer.writeln('──────────────────');
    for (final item in _items) {
      final itemModel = InvoiceItem.fromMap(item);
      buffer.writeln('${itemModel.productName} × ${itemModel.quantity} = ${CurrencyFormatter.format(itemModel.totalPrice)}');
    }
    Share.share(buffer.toString(), subject: _invoiceTypeAr);
  }

  void _shareInvoiceWhatsApp() {
    if (_invoice == null) return;
    final buffer = StringBuffer();
    buffer.writeln('*$_invoiceTypeAr*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('رقم: ${_displayInvoiceId(_invoice?['id'] as String?)}');
    buffer.writeln('${_isSale ? 'العميل' : 'المورد'}: *$_entityName*');
    buffer.writeln('*الإجمالي: ${CurrencyFormatter.format(MoneyHelper.readMoney(_invoice?['total']))}*');
    buffer.writeln('المدفوع: ${CurrencyFormatter.format(MoneyHelper.readMoney(_invoice?['paid_amount']))}');
    buffer.writeln('المتبقي: ${CurrencyFormatter.format(MoneyHelper.readMoney(_invoice?['remaining']))}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    for (final item in _items) {
      final itemModel = InvoiceItem.fromMap(item);
      buffer.writeln('▫️ ${itemModel.productName} × ${itemModel.quantity} = ${CurrencyFormatter.format(itemModel.totalPrice)}');
    }
    Share.share(buffer.toString(), subject: _invoiceTypeAr);
  }

  Future<void> _printInvoice() async {
    if (_invoice == null) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري إنشاء ملف PDF...'), duration: Duration(seconds: 1)),
      );
      final invoiceMap = <String, dynamic>{
        ..._invoice!,
        'entity_name': _entityName,
      };
      await InvoicePdfGenerator.printInvoice(invoiceMap, _items);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('حدث خطأ أثناء الطباعة');
    }
  }
}
