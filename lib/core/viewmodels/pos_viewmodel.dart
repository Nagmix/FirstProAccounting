import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
import '../../data/datasources/repositories/product_repository.dart';
import '../../data/datasources/repositories/reference_data_repository.dart';
import '../../data/datasources/repositories/invoice_repository.dart';
import '../../data/datasources/services/cash_box_service.dart';
import '../../data/datasources/services/shift_service.dart';
import '../../data/datasources/services/report_service.dart';
import '../../data/models/product_model.dart';
import '../utils/money_helper.dart';
import '../../ui/screens/pos/pos_models.dart';

/// ViewModel for POS screen — manages POS data state and enables
/// reactive updates for sync readiness.
///
/// This ViewModel serves as the single source of truth for POS display data.
/// The screen reads state from here and calls mutation methods.
/// When data changes (e.g., from sync), calling [refresh] or individual
/// reload methods will automatically update any listening UI.
///
/// UI controllers (TextEditingController, FocusNode, DraggableScrollableController,
/// Ticker) remain in the screen since they are UI-layer concerns.
///
/// Registered in [service_locator.dart] as a lazy singleton.
class PosViewModel extends ChangeNotifier {
  // ── Dependencies ──
  final ProductRepository _productRepo = locator<ProductRepository>();
  final ReferenceDataRepository _refData = locator<ReferenceDataRepository>();
  final InvoiceRepository _invoiceRepo = locator<InvoiceRepository>();
  final CashBoxService _cashBoxService = locator<CashBoxService>();
  final ShiftService _shiftService = locator<ShiftService>();
  final ReportService _reportService = locator<ReportService>();

  // ══════════════════════════════════════════════════════════════════
  //  PRODUCT & CATEGORY STATE
  // ══════════════════════════════════════════════════════════════════

  List<Product> _products = [];
  List<Product> get products => _products;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> get categories => _categories;

  int? _selectedCategoryId;
  int? get selectedCategoryId => _selectedCategoryId;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  /// Filter products by category, search query, and POS visibility.
  List<Product> get filteredProducts {
    var result = _products;
    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((p) =>
          p.nameAr.contains(q) ||
          p.nameEn.toLowerCase().contains(q) ||
          (p.barcode ?? '').contains(q)).toList();
    }
    return result;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════
  //  CART STATE
  // ══════════════════════════════════════════════════════════════════

  final List<CartItem> _cartItems = [];
  List<CartItem> get cartItems => _cartItems;

  double _orderDiscount = 0;
  double get orderDiscount => _orderDiscount;

  DiscountType _discountType = DiscountType.fixed;
  DiscountType get discountType => _discountType;

  int? _selectedCustomerId;
  int? get selectedCustomerId => _selectedCustomerId;

  String _selectedCustomerName = '';
  String get selectedCustomerName => _selectedCustomerName;

  // ── Payment state ──
  final List<PaymentEntry> _payments = [];
  List<PaymentEntry> get payments => _payments;

  String _activePaymentMethod = 'cash';
  String get activePaymentMethod => _activePaymentMethod;

  // ── Checkout state ──
  CheckoutPhase _checkoutPhase = CheckoutPhase.idle;
  CheckoutPhase get checkoutPhase => _checkoutPhase;

  String _lastInvoiceId = '';
  String get lastInvoiceId => _lastInvoiceId;

  double _capturedTotal = 0;
  double get capturedTotal => _capturedTotal;
  String _capturedCustomerName = '';
  double get capturedCustomerNameVal => 0; // unused but kept for compat
  String get capturedPaymentLabel => _capturedPaymentLabel;
  int _capturedCartLength = 0;
  int get capturedCartLength => _capturedCartLength;
  double _capturedSubtotal = 0;
  double get capturedSubtotal => _capturedSubtotal;
  double _capturedDiscount = 0;
  double get capturedDiscount => _capturedDiscount;
  double _capturedTax = 0;
  double get capturedTax => _capturedTax;
  String _capturedPaymentLabel = '';

  // ── Computed cart properties ──

  double get subtotal => _cartItems.fold(0.0, (sum, i) => sum + i.total);

  double get effectiveDiscount {
    if (_discountType == DiscountType.percentage) {
      return subtotal * (_orderDiscount / 100);
    }
    return _orderDiscount;
  }

  double get tax => (subtotal - effectiveDiscount) * 0.0; // VAT placeholder
  double get total => subtotal - effectiveDiscount + tax;

  double get totalPaid => _payments.fold(0.0, (sum, p) => sum + p.amount);
  double get remaining => total - totalPaid;

  int get itemCount => _cartItems.length;

  // ── Cart mutations ──

  void setOrderDiscount(double value, DiscountType type) {
    _orderDiscount = value;
    _discountType = type;
    _syncPaymentsWithTotal();
    notifyListeners();
  }

  void setSelectedCustomer(int? id, String name) {
    _selectedCustomerId = id;
    _selectedCustomerName = name;
    notifyListeners();
  }

  void setActivePaymentMethod(String method) {
    _activePaymentMethod = method;
    if (_payments.length == 1) {
      _payments[0] = PaymentEntry(method: method, amount: _payments[0].amount);
    }
    notifyListeners();
  }

  /// Add a product to cart with a specific unit.
  void addToCartDirect(Product product, Map<String, dynamic>? unitInfo) {
    if (product.id == null) return; // Guard: unsaved product cannot be added
    final unitName = unitInfo?['unit_name'] as String? ?? 'قطعة';
    final sellPrice = unitInfo != null
        ? MoneyHelper.readMoney(unitInfo['sell_price'], fallback: product.sellPrice)
        : product.sellPrice;
    final conversionFactor = (unitInfo?['conversion_factor'] as num?)?.toDouble() ?? 1.0;
    final unitBarcode = unitInfo?['barcode'] as String?;

    final existingIndex = _cartItems.indexWhere((item) =>
        item.productId == product.id && item.unitName == unitName);

    if (existingIndex >= 0) {
      _cartItems[existingIndex] = _cartItems[existingIndex].copyWith(
        quantity: _cartItems[existingIndex].quantity + 1,
      );
    } else {
      _cartItems.add(CartItem(
        productId: product.id!,
        name: product.nameAr,
        unitPrice: sellPrice,
        quantity: 1,
        unitName: unitName,
        conversionFactor: conversionFactor,
        unitBarcode: unitBarcode,
      ));
    }

    // Auto-create default payment if none exists
    if (_payments.isEmpty) {
      _payments.add(PaymentEntry(method: _activePaymentMethod, amount: total));
    } else {
      _syncPaymentsWithTotal();
    }
    notifyListeners();
  }

  /// Add a product to cart (base unit).
  void addToCart(Product product) {
    addToCartDirect(product, null);
  }

  void incrementCart(int index) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems[index] = _cartItems[index].copyWith(
        quantity: _cartItems[index].quantity + 1,
      );
      _syncPaymentsWithTotal();
      notifyListeners();
    }
  }

  void decrementCart(int index) {
    if (index >= 0 && index < _cartItems.length) {
      if (_cartItems[index].quantity <= 1) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index] = _cartItems[index].copyWith(
          quantity: _cartItems[index].quantity - 1,
        );
      }
      _syncPaymentsWithTotal();
      notifyListeners();
    }
  }

  void updateCartQuantity(int index, int quantity) {
    if (index >= 0 && index < _cartItems.length) {
      if (quantity <= 0) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index] = _cartItems[index].copyWith(quantity: quantity);
      }
      _syncPaymentsWithTotal();
      notifyListeners();
    }
  }

  void removeFromCart(int index) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems.removeAt(index);
      _syncPaymentsWithTotal();
      notifyListeners();
    }
  }

  void addPayment(PaymentEntry entry) {
    _payments.add(entry);
    notifyListeners();
  }

  void removePayment(int index) {
    if (index >= 0 && index < _payments.length) {
      _payments.removeAt(index);
      notifyListeners();
    }
  }

  void updatePayment(int index, PaymentEntry entry) {
    if (index >= 0 && index < _payments.length) {
      _payments[index] = entry;
      notifyListeners();
    }
  }

  void _syncPaymentsWithTotal() {
    if (_payments.length == 1) {
      _payments[0] = PaymentEntry(method: _payments[0].method, amount: total);
    }
  }

  /// Capture checkout snapshot.
  void captureCheckoutSnapshot() {
    _capturedTotal = total;
    _capturedCustomerName = _selectedCustomerName;
    _capturedPaymentLabel = _paymentLabel(_activePaymentMethod);
    _capturedCartLength = _cartItems.length;
    _capturedSubtotal = subtotal;
    _capturedDiscount = effectiveDiscount;
    _capturedTax = tax;
  }

  void setCheckoutPhase(CheckoutPhase phase) {
    _checkoutPhase = phase;
    notifyListeners();
  }

  void setLastInvoiceId(String id) {
    _lastInvoiceId = id;
    notifyListeners();
  }

  /// Reset for a new invoice after successful checkout.
  void resetForNewInvoice() {
    _cartItems.clear();
    _orderDiscount = 0;
    _discountType = DiscountType.fixed;
    _selectedCustomerId = null;
    _selectedCustomerName = '';
    _payments.clear();
    _activePaymentMethod = 'cash';
    _searchQuery = '';
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════
  //  SHIFT STATE
  // ══════════════════════════════════════════════════════════════════

  Map<String, dynamic>? _activeShift;
  Map<String, dynamic>? get activeShift => _activeShift;

  String _shiftCashBoxName = '';
  String get shiftCashBoxName => _shiftCashBoxName;

  String _cashierName = '';
  String get cashierName => _cashierName;

  Duration _shiftDuration = Duration.zero;
  Duration get shiftDuration => _shiftDuration;

  /// Update shift duration (called by screen ticker).
  void updateShiftDuration() {
    if (_activeShift != null && _activeShift!['opened_at'] != null) {
      final opened = DateTime.parse(_activeShift!['opened_at'].toString());
      _shiftDuration = DateTime.now().difference(opened);
      notifyListeners();
    }
  }

  String get formattedShiftDuration {
    final d = _shiftDuration;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Get the shift's total sales amount.
  double get shiftTotalSales {
    if (_activeShift == null) return 0;
    return MoneyHelper.readMoney(_activeShift!['total_sales']);
  }

  /// Get the shift's opening amount.
  double get shiftOpeningAmount {
    if (_activeShift == null) return 0;
    return MoneyHelper.readMoney(_activeShift!['opening_amount']);
  }

  // ══════════════════════════════════════════════════════════════════
  //  HELD ORDERS
  // ══════════════════════════════════════════════════════════════════

  final List<HeldOrder> _heldOrders = [];
  List<HeldOrder> get heldOrders => _heldOrders;

  // ══════════════════════════════════════════════════════════════════
  //  CURRENCY STATE
  // ══════════════════════════════════════════════════════════════════

  String _selectedCurrency = 'YER';
  String get selectedCurrency => _selectedCurrency;

  void setSelectedCurrency(String currency) {
    _selectedCurrency = currency;
    notifyListeners();
  }

  /// Currency symbol for display.
  String get currencySymbol {
    switch (_selectedCurrency) {
      case 'SAR': return 'ر.س';
      case 'USD': return '\$';
      default: return 'ر.ي';
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  TOP SELLERS
  // ══════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _topSellers = [];
  List<Map<String, dynamic>> get topSellers => _topSellers;

  // ══════════════════════════════════════════════════════════════════
  //  LOADING & ERROR STATE
  // ══════════════════════════════════════════════════════════════════

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _todayInvoiceCount = 0;
  int get todayInvoiceCount => _todayInvoiceCount;

  // ══════════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ══════════════════════════════════════════════════════════════════

  /// Load all initial data for the POS screen.
  Future<void> loadData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _refData.getAllCategories(),
        _productRepo.getAllProducts(activeOnly: true),
      ]);

      _categories = results[0] as List<Map<String, dynamic>>;
      final prodMaps = results[1] as List<Map<String, dynamic>>;

      _products = prodMaps
          .map((m) => Product.fromMap(m))
          .where((p) => p.isSellable && p.showInPos)
          .toList();

      // Load default cashier name
      final savedName = await _refData.getSetting('user_name');
      if (savedName != null && savedName.isNotEmpty) {
        _cashierName = savedName;
      }

      // Today's invoice count
      final today = DateTime.now();
      final todayStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      _todayInvoiceCount = await _invoiceRepo.getTodayPosInvoiceCount(todayStr);

      _isLoading = false;
      notifyListeners();

      await _loadActiveShift();
      await _loadHeldOrdersFromDb();
      await _loadTopSellers();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
      debugPrint('PosViewModel loadData error: $e');
      notifyListeners();
    }
  }

  Future<void> _loadActiveShift() async {
    final cashBoxes = await _cashBoxService.getAllCashBoxes();
    for (final cb in cashBoxes) {
      final shift = await _shiftService.getActiveShift(cb['id'] as int);
      if (shift != null) {
        _activeShift = shift;
        _shiftCashBoxName = (cb['name'] ?? '').toString();
        if (shift['cashier_name'] != null) {
          _cashierName = shift['cashier_name'].toString();
        }
        _selectedCurrency = (shift['currency'] ?? cb['currency'] ?? 'YER').toString();
        notifyListeners();
        return;
      }
    }
    _activeShift = null;
    _shiftCashBoxName = '';
    _shiftDuration = Duration.zero;
    notifyListeners();
  }

  Future<void> _loadHeldOrdersFromDb() async {
    try {
      _heldOrders.clear();
      final dbOrders = await _shiftService.getHeldOrders(shiftId: _activeShift?['id']);
      for (final row in dbOrders) {
        final cartData = jsonDecode(row['cart_data'] as String) as List;
        final paymentsData = jsonDecode(row['payments_data'] as String) as List;
        final cartItems = cartData.map((item) => CartItem(
          productId: item['productId'] as int,
          name: item['productName'] as String,
          quantity: (item['quantity'] as num).toInt(),
          unitPrice: MoneyHelper.readMoney(item['unitPrice']),
          unitName: item['unitName'] as String? ?? 'قطعة',
          conversionFactor: (item['conversionFactor'] as num?)?.toDouble() ?? 1.0,
        )).toList();
        final payments = paymentsData.map((p) => PaymentEntry(
          amount: MoneyHelper.readMoney(p['amount']),
          method: p['method'] as String? ?? 'cash',
        )).toList();
        final discountTypeStr = row['discount_type'] as String? ?? 'fixed';
        _heldOrders.add(HeldOrder(
          items: cartItems,
          paymentMethod: row['payment_method'] as String? ?? 'cash',
          payments: payments,
          discount: MoneyHelper.readMoney(row['discount']),
          discountType: DiscountType.values.firstWhere((e) => e.name == discountTypeStr, orElse: () => DiscountType.fixed),
          customerId: row['customer_id'] as int?,
          customerName: row['customer_name'] as String? ?? '',
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
          dbId: row['id'] as int?,
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Warning: Could not load held orders from DB: $e');
    }
  }

  Future<void> _loadTopSellers() async {
    try {
      final today = DateTime.now();
      final todayStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      _topSellers = await _reportService.getTopSellersToday(todayStr);
      notifyListeners();
    } catch (e) {
      debugPrint('Warning: Could not load top sellers: $e');
    }
  }

  Future<void> _refreshProducts() async {
    try {
      final prodMaps = await _productRepo.getAllProducts(activeOnly: true);
      _products = prodMaps
          .map((m) => Product.fromMap(m))
          .where((p) => p.isSellable && p.showInPos)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Warning: Could not refresh products: $e');
    }
  }

  /// Try to match a barcode to a product or unit conversion.
  Future<BarcodeMatchResult?> tryBarcodeMatch(String barcode) async {
    // 1. Check direct product barcode
    final match = _products.where(
      (p) => (p.barcode ?? '').trim() == barcode.trim(),
    );
    if (match.isNotEmpty) {
      return BarcodeMatchResult(product: match.first, unitInfo: null);
    }

    // 2. Check unit conversion barcodes
    final conversion = await _refData.findUnitConversionByBarcode(barcode);
    if (conversion != null) {
      final productId = conversion['product_id'] as int;
      final product = _products.where((p) => p.id == productId).firstOrNull;
      if (product != null) {
        return BarcodeMatchResult(product: product, unitInfo: {
          'unit_name': conversion['from_unit'] as String,
          'sell_price': MoneyHelper.readMoney(conversion['sell_price'], fallback: product.sellPrice),
          'conversion_factor': (conversion['conversion_factor'] as num?)?.toDouble() ?? 1.0,
          'barcode': conversion['barcode'] as String?,
        });
      }
    }
    return null;
  }

  /// Get available units for a product.
  Future<List<Map<String, dynamic>>?> getAvailableUnitsForProduct(int productId) async {
    return await _refData.getAvailableUnitsForProduct(productId);
  }

  // ══════════════════════════════════════════════════════════════════
  //  SHIFT OPERATIONS (delegate to services)
  // ══════════════════════════════════════════════════════════════════

  /// Open a new shift — delegates to ShiftService.
  Future<void> openShift(Map<String, dynamic> shiftMap) async {
    await _shiftService.openShift(shiftMap);
    await _refData.setSetting('user_name', _cashierName);
    await _loadActiveShift();
    await _loadHeldOrdersFromDb();
  }

  /// Close shift — delegates to ShiftService.
  Future<void> closeShift(int shiftId, Map<String, dynamic> closeData) async {
    await _shiftService.postShiftInvoices(shiftId);
    await _shiftService.closeShift(shiftId, closeData);
    _activeShift = null;
    _shiftCashBoxName = '';
    _shiftDuration = Duration.zero;
    _heldOrders.clear();
    notifyListeners();
  }

  /// Update shift cashier name.
  void updateCashierName(String name) {
    _cashierName = name;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════
  //  HELD ORDER OPERATIONS
  // ══════════════════════════════════════════════════════════════════

  /// Hold the current order and persist to DB.
  Future<void> holdOrder() async {
    if (_cartItems.isEmpty) return;

    final order = HeldOrder(
      items: List.from(_cartItems),
      paymentMethod: _activePaymentMethod,
      payments: List.from(_payments),
      discount: _orderDiscount,
      discountType: _discountType,
      customerId: _selectedCustomerId,
      customerName: _selectedCustomerName,
      createdAt: DateTime.now(),
    );

    // Persist to DB
    final cartJson = jsonEncode(_cartItems.map((i) => {
      'productId': i.productId,
      'productName': i.name,
      'quantity': i.quantity,
      'unitPrice': MoneyHelper.toCents(i.unitPrice),
      'unitName': i.unitName,
      'conversionFactor': i.conversionFactor,
    }).toList());
    final paymentsJson = jsonEncode(_payments.map((p) => {
      'method': p.method,
      'amount': MoneyHelper.toCents(p.amount),
    }).toList());

    final dbId = await _shiftService.insertHeldOrder({
      'shift_id': _activeShift?['id'],
      'cart_data': cartJson,
      'payments_data': paymentsJson,
      'payment_method': _activePaymentMethod,
      'discount': MoneyHelper.toCents(_orderDiscount),
      'discount_type': _discountType.name,
      'customer_id': _selectedCustomerId,
      'customer_name': _selectedCustomerName,
      'created_at': DateTime.now().toIso8601String(),
    });

    _heldOrders.add(HeldOrder(
      items: order.items,
      paymentMethod: order.paymentMethod,
      payments: order.payments,
      discount: order.discount,
      discountType: order.discountType,
      customerId: order.customerId,
      customerName: order.customerName,
      createdAt: order.createdAt,
      dbId: dbId,
    ));

    resetForNewInvoice();
  }

  /// Restore a held order.
  void restoreHeldOrder(int index) {
    if (index < 0 || index >= _heldOrders.length) return;
    final order = _heldOrders[index];
    _cartItems.clear();
    _cartItems.addAll(order.items);
    _payments.clear();
    _payments.addAll(order.payments);
    _orderDiscount = order.discount;
    _discountType = order.discountType;
    _selectedCustomerId = order.customerId;
    _selectedCustomerName = order.customerName;
    _activePaymentMethod = order.paymentMethod;
    _heldOrders.removeAt(index);
    notifyListeners();
  }

  /// Delete a held order.
  Future<void> deleteHeldOrder(int index) async {
    if (index < 0 || index >= _heldOrders.length) return;
    final order = _heldOrders[index];
    if (order.dbId != null) {
      await _shiftService.deleteHeldOrder(order.dbId!);
    }
    _heldOrders.removeAt(index);
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════
  //  INVOICE ID GENERATION
  // ══════════════════════════════════════════════════════════════════

  Future<String> generateInvoiceId() async {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final nextSeq = await _invoiceRepo.getNextInvoiceSequence('POS-$dateStr', 'pos');
    _todayInvoiceCount = nextSeq;
    final seq = nextSeq.toString().padLeft(4, '0');
    return 'POS-$dateStr-$seq';
  }

  // ══════════════════════════════════════════════════════════════════
  //  UTILITY
  // ══════════════════════════════════════════════════════════════════

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash': return 'نقدي';
      case 'card': return 'بطاقة';
      case 'ewallet': return 'محفظة إلكترونية';
      case 'bank_transfer': return 'تحويل بنكي';
      case 'credit': return 'آجل';
      default: return method;
    }
  }
}

/// Result of a barcode match attempt.
class BarcodeMatchResult {
  final Product product;
  final Map<String, dynamic>? unitInfo;

  const BarcodeMatchResult({required this.product, this.unitInfo});
}
