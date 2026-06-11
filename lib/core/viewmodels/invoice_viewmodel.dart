import 'package:flutter/foundation.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/customer_repository.dart';
import 'package:firstpro/data/datasources/repositories/supplier_repository.dart';
import 'package:firstpro/data/datasources/repositories/product_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:firstpro/data/models/invoice_item_model.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ViewModel for invoice creation — manages customers, products, invoice items,
/// entity selection, payment state, currency, and all computed totals.
///
/// Uses dependency-injected repositories/services instead of DatabaseHelper
/// directly. Registered in [service_locator.dart] as a lazy singleton.
class InvoiceViewModel extends ChangeNotifier {
  final CustomerRepository _customerRepo = locator<CustomerRepository>();
  final SupplierRepository _supplierRepo = locator<SupplierRepository>();
  // ignore: unused_field
  final ProductRepository _productRepo = locator<ProductRepository>();
  final ReferenceDataRepository _referenceDataRepo =
      locator<ReferenceDataRepository>();
  final CashBoxService _cashBoxService = locator<CashBoxService>();

  // ── Customer state ──
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> get customers => _customers;

  // ── Supplier state ──
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> get suppliers => _suppliers;

  // ── Combined entities (customers + suppliers) ──
  List<Map<String, dynamic>> _combinedEntities = [];
  List<Map<String, dynamic>> get combinedEntities => _combinedEntities;

  List<Map<String, dynamic>> _filteredEntities = [];
  List<Map<String, dynamic>> get filteredEntities => _filteredEntities;

  // ── Product state ──
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> get products => _products;

  // ── Reference data ──
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> get warehouses => _warehouses;

  List<Map<String, dynamic>> _cashBoxes = [];
  List<Map<String, dynamic>> get cashBoxes => _cashBoxes;

  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> get currencies => _currencies;

  // ── Invoice items ──
  final List<InvoiceItem> _items = [];
  List<InvoiceItem> get items => List.unmodifiable(_items);

  // ── Entity selection — unified: customers + suppliers ──
  int? _selectedEntityId;
  int? get selectedEntityId => _selectedEntityId;

  String? _selectedEntityType; // 'customer' or 'supplier'
  String? get selectedEntityType => _selectedEntityType;

  int? _selectedWarehouseId;
  int? get selectedWarehouseId => _selectedWarehouseId;

  int? _selectedCashBoxId;
  int? get selectedCashBoxId => _selectedCashBoxId;

  // ── Invoice type ──
  String _invoiceType = 'sale';
  String get invoiceType => _invoiceType;

  // ── Payment state ──
  String _paymentMechanism = 'cash';
  String get paymentMechanism => _paymentMechanism;

  // Payment method: cash, check, transfer, bank, ewallet, bank_transfer
  String _paymentMethod = 'cash';
  String get paymentMethod => _paymentMethod;

  // ── Is return invoice ──
  bool _isReturn = false;
  bool get isReturn => _isReturn;

  // ── Auto-pay checkbox ──
  bool _autoPay = true;
  bool get autoPay => _autoPay;

  // ── Discount & transport ──
  double _discount = 0.0;
  double get discount => _discount;

  double _transportCharges = 0.0;
  double get transportCharges => _transportCharges;

  // ── Paid amount ──
  double _paidAmount = 0.0;
  double get paidAmountValue => _paidAmount;

  // ── Currency ──
  String _selectedCurrency = 'YER';
  String get selectedCurrency => _selectedCurrency;

  double _selectedExchangeRate = 1.0;
  double get selectedExchangeRate => _selectedExchangeRate;

  // ── E-wallet state ──
  String? _selectedEwalletProvider;
  String? get selectedEwalletProvider => _selectedEwalletProvider;

  // ── Bank transfer state ──
  String? _selectedBankTransferProvider;
  String? get selectedBankTransferProvider => _selectedBankTransferProvider;

  // ── Attachment image ──
  String? _attachmentPath;
  String? get attachmentPath => _attachmentPath;

  // ── Original invoice for returns ──
  String? _originalInvoiceId;
  String? get originalInvoiceId => _originalInvoiceId;

  String? _originalInvoiceDisplay;
  String? get originalInvoiceDisplay => _originalInvoiceDisplay;

  // ── Show entity dropdown ──
  bool _showEntityDropdown = false;
  bool get showEntityDropdown => _showEntityDropdown;

  // ── Loading state ──
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ── Computed properties ────────────────────────────────────────────

  /// Subtotal before discount and tax.
  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Discount amount (from stored value).
  double get discountAmount => _discount;

  /// Transport charges (from stored value).
  double get transportChargesAmount => _transportCharges;

  double _vatRate = 0.0;
  double get vatRate => _vatRate;

  /// Tax amount based on VAT rate.
  double get taxAmount =>
      (subtotal - discountAmount) * (_vatRate / 100);

  /// Total after discount, tax, and transport.
  double get total =>
      subtotal - discountAmount + taxAmount + transportChargesAmount;

  /// Paid amount (from stored value).
  double get paidAmount => _paidAmount;

  /// Remaining amount to be paid.
  double get remaining => total - paidAmount;

  /// Total in base currency (YER).
  double get totalInBaseCurrency => total * _selectedExchangeRate;

  /// Paid amount in base currency.
  double get paidAmountInBaseCurrency => paidAmount * _selectedExchangeRate;

  /// Remaining in base currency.
  double get remainingInBaseCurrency => remaining * _selectedExchangeRate;

  /// Total items count.
  int get itemCount => _items.length;

  /// Whether entity is required (credit mechanism or partial payment).
  bool get isEntityRequired =>
      _paymentMechanism == 'credit' || remaining > 0.005;

  /// Whether this is a sale invoice.
  bool get isSale => _invoiceType == 'sale';

  /// Selected entity name.
  String? get selectedEntityName {
    if (_selectedEntityId == null) return null;
    final entity = _combinedEntities
        .where(
          (e) =>
              e['id'] == _selectedEntityId && e['type'] == _selectedEntityType,
        )
        .firstOrNull;
    return entity?['name'] as String?;
  }

  /// Title for the screen.
  String get title {
    String base = isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات';
    if (_isReturn) base = 'فاتورة مرتجع $base';
    return '$base جديدة';
  }

  /// Whether to show partial payment warning.
  bool get showPartialPaymentWarning =>
      !_autoPay &&
      _paymentMechanism == 'cash' &&
      paidAmount > 0 &&
      remaining > 0.005;

  // ── Data loading ───────────────────────────────────────────────────

  /// Load initial data (customers, suppliers, warehouses, cash boxes, currencies).
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
        _referenceDataRepo.getAllWarehouses(),
        _cashBoxService.getAllCashBoxes(),
        _referenceDataRepo.getAllCurrencies(),
      ]);
      _customers = results[0];
      _suppliers = results[1];
      _warehouses = results[2];
      _cashBoxes = results[3];
      _currencies = results[4];
      _buildCombinedEntities();

      // Sync VAT rate for current selected currency
      final cRow = _currencies.where((c) => c['code'] == _selectedCurrency).firstOrNull;
      if (cRow != null) {
        _vatRate = (cRow['vat_rate'] as num?)?.toDouble() ?? 0.0;
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
      debugPrint('InvoiceViewModel loadData error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reload entities after adding a new customer/supplier.
  Future<void> reloadEntities() async {
    try {
      final results = await Future.wait([
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
      ]);
      _customers = results[0];
      _suppliers = results[1];
      _buildCombinedEntities();
      notifyListeners();
    } catch (e) {
      debugPrint('InvoiceViewModel reloadEntities error: $e');
    }
  }

  // ── Combined entity helpers ────────────────────────────────────────

  void _buildCombinedEntities() {
    _combinedEntities = [];
    for (final c in _customers) {
      _combinedEntities.add({
        'id': c['id'],
        'name': c['name'],
        'type': 'customer',
        'balance': MoneyHelper.readMoney(c['balance']),
        'balance_type': c['balance_type'] ?? 'credit',
      });
    }
    for (final s in _suppliers) {
      _combinedEntities.add({
        'id': s['id'],
        'name': s['name'],
        'type': 'supplier',
        'balance': MoneyHelper.readMoney(s['balance']),
        'balance_type': s['balance_type'] ?? 'credit',
      });
    }
    _filteredEntities = List.from(_combinedEntities);
  }

  void filterEntities(String query) {
    if (query.isEmpty) {
      _filteredEntities = List.from(_combinedEntities);
    } else {
      final q = query.toLowerCase();
      _filteredEntities = _combinedEntities.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        return name.contains(q);
      }).toList();
    }
    notifyListeners();
  }

  // ── Setters ────────────────────────────────────────────────────────

  void setInvoiceType(String type) {
    _invoiceType = type;
    notifyListeners();
  }

  void setCustomer(int? customerId) {
    _selectedEntityId = customerId;
    _selectedEntityType = customerId != null ? 'customer' : null;
    notifyListeners();
  }

  void setEntity(int? entityId, String? entityType) {
    _selectedEntityId = entityId;
    _selectedEntityType = entityType;
    notifyListeners();
  }

  void clearEntity() {
    _selectedEntityId = null;
    _selectedEntityType = null;
    notifyListeners();
  }

  void setWarehouse(int? warehouseId) {
    _selectedWarehouseId = warehouseId;
    notifyListeners();
  }

  void setCashBox(int? cashBoxId) {
    _selectedCashBoxId = cashBoxId;
    notifyListeners();
  }

  void setPaymentMechanism(String mechanism) {
    _paymentMechanism = mechanism;
    notifyListeners();
  }

  /// Set to cash mechanism with side effects.
  void setCashMechanism() {
    _paymentMechanism = 'cash';
    notifyListeners();
  }

  /// Set to credit mechanism with side effects.
  void setCreditMechanism() {
    _paymentMechanism = 'credit';
    _selectedCashBoxId = null;
    _autoPay = false;
    _paidAmount = 0.0;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    if (method != 'ewallet') _selectedEwalletProvider = null;
    if (method != 'bank_transfer') {
      _selectedBankTransferProvider = null;
    }
    if (method != 'ewallet' && method != 'bank_transfer') {
      _attachmentPath = null;
    }
    notifyListeners();
  }

  void toggleReturn() {
    _isReturn = !_isReturn;
    notifyListeners();
  }

  void setReturn(bool value) {
    _isReturn = value;
    notifyListeners();
  }

  void toggleAutoPay() {
    _autoPay = !_autoPay;
    if (_autoPay && total > 0) {
      _paidAmount = total;
    }
    notifyListeners();
  }

  void setAutoPay(bool value) {
    _autoPay = value;
    if (_autoPay && total > 0) {
      _paidAmount = total;
    }
    notifyListeners();
  }

  /// Update auto-pay paid amount when totals change.
  void updateAutoPay() {
    if (_autoPay && total > 0) {
      _paidAmount = total;
      notifyListeners();
    }
  }

  void setDiscount(double value) {
    _discount = value;
    notifyListeners();
  }

  void setTransportCharges(double value) {
    _transportCharges = value;
    notifyListeners();
  }

  void setPaidAmount(double value) {
    _paidAmount = value;
    notifyListeners();
  }

  void setCurrency(String currencyCode) {
    _selectedCurrency = currencyCode;
    final currency =
        _currencies.where((c) => c['code'] == currencyCode).firstOrNull;
    if (currency != null) {
      _selectedExchangeRate =
          (currency['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      _vatRate = (currency['vat_rate'] as num?)?.toDouble() ?? 0.0;
    }
    notifyListeners();
  }

  void setEwalletProvider(String? provider) {
    _selectedEwalletProvider = provider;
    notifyListeners();
  }

  void setBankTransferProvider(String? provider) {
    _selectedBankTransferProvider = provider;
    notifyListeners();
  }

  void setAttachmentPath(String? path) {
    _attachmentPath = path;
    notifyListeners();
  }

  void setOriginalInvoice(String? invoiceId, String? display) {
    _originalInvoiceId = invoiceId;
    _originalInvoiceDisplay = display;
    notifyListeners();
  }

  void clearOriginalInvoice() {
    _originalInvoiceId = null;
    _originalInvoiceDisplay = null;
    notifyListeners();
  }

  void toggleEntityDropdown() {
    _showEntityDropdown = !_showEntityDropdown;
    notifyListeners();
  }

  void setShowEntityDropdown(bool value) {
    _showEntityDropdown = value;
    notifyListeners();
  }

  /// Select entity and reset dropdown/search state.
  void selectEntity(int id, String type) {
    _selectedEntityId = id;
    _selectedEntityType = type;
    _showEntityDropdown = false;
    _filteredEntities = List.from(_combinedEntities);
    notifyListeners();
  }

  // ── Item management ────────────────────────────────────────────────

  /// Add an invoice item directly.
  void addItem(InvoiceItem item) {
    _items.add(item);
    updateAutoPay();
  }

  /// Add a product as an invoice item (from product map).
  void addItemFromProduct(Map<String, dynamic> product) {
    final productId = product['id'] as int;
    final existingIndex =
        _items.indexWhere((item) => item.productId == productId);
    if (existingIndex >= 0) {
      final existing = _items[existingIndex];
      _items[existingIndex] = existing.copyWith(
        quantity: existing.quantity + 1,
        totalPrice: (existing.quantity + 1) * existing.unitPrice,
      );
    } else {
      _items.add(InvoiceItem(
        invoiceId: '',
        productId: productId,
        productName: product['name_ar'] as String? ?? '',
        unitPrice: MoneyHelper.readMoney(product['sell_price']),
        quantity: 1,
        totalPrice: MoneyHelper.readMoney(product['sell_price']),
        unitCost: MoneyHelper.readMoney(product['average_cost']) > 0
            ? MoneyHelper.readMoney(product['average_cost'])
            : MoneyHelper.readMoney(product['cost_price']),
        baseQuantity: 1.0,
      ));
    }
    updateAutoPay();
    notifyListeners();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      updateAutoPay();
      notifyListeners();
    }
  }

  void updateItemQuantity(int index, double quantity) {
    if (index >= 0 && index < _items.length) {
      final item = _items[index];
      _items[index] = item.copyWith(
        quantity: quantity,
        totalPrice: quantity * item.unitPrice,
      );
      updateAutoPay();
      notifyListeners();
    }
  }

  void updateItemPrice(int index, double price) {
    if (index >= 0 && index < _items.length) {
      final item = _items[index];
      _items[index] = item.copyWith(
        unitPrice: price,
        totalPrice: item.quantity * price,
      );
      notifyListeners();
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────

  /// Clear all items and reset state.
  void clear() {
    _items.clear();
    _discount = 0.0;
    _transportCharges = 0.0;
    _paidAmount = 0.0;
    _selectedEntityId = null;
    _selectedEntityType = null;
    _selectedCashBoxId = null;
    _selectedWarehouseId = null;
    _paymentMechanism = 'cash';
    _paymentMethod = 'cash';
    _isReturn = false;
    _autoPay = true;
    _selectedCurrency = 'YER';
    _selectedExchangeRate = 1.0;
    _vatRate = 0.0;
    _selectedEwalletProvider = null;
    _selectedBankTransferProvider = null;
    _attachmentPath = null;
    _originalInvoiceId = null;
    _originalInvoiceDisplay = null;
    _showEntityDropdown = false;
    notifyListeners();
  }
}
