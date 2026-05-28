import 'package:flutter/foundation.dart';
import '../../data/datasources/database_helper.dart';
import '../../core/utils/money_helper.dart';

/// ViewModel for invoice creation — manages customers, products, and invoice items.
/// Extracted from CreateInvoiceScreen State (H-08).
class InvoiceViewModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  // ── Customer state ──
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> get customers => _customers;

  // ── Product state ──
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> get products => _products;

  // ── Invoice items ──
  final List<InvoiceItem> _items = [];
  List<InvoiceItem> get items => List.unmodifiable(_items);

  int? _selectedCustomerId;
  int? get selectedCustomerId => _selectedCustomerId;

  String _invoiceType = 'sale';
  String get invoiceType => _invoiceType;

  String _paymentMechanism = 'cash';
  String get paymentMechanism => _paymentMechanism;

  double _discount = 0.0;
  double get discount => _discount;

  double _transportCharges = 0.0;
  double get transportCharges => _transportCharges;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Load initial data (customers and products).
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _customers = await _db.getAllCustomers();
      _products = await _db.getAllProducts();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
      debugPrint('InvoiceViewModel loadData error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setCustomer(int? customerId) {
    _selectedCustomerId = customerId;
    notifyListeners();
  }

  void setInvoiceType(String type) {
    _invoiceType = type;
    notifyListeners();
  }

  void setPaymentMechanism(String mechanism) {
    _paymentMechanism = mechanism;
    notifyListeners();
  }

  void setDiscount(double value) {
    _discount = value;
    notifyListeners();
  }

  void setTransportCharges(double value) {
    _transportCharges = value;
    notifyListeners();
  }

  /// Add a product as an invoice item.
  void addItem(Map<String, dynamic> product) {
    final productId = product['id'] as int;
    final existingIndex = _items.indexWhere((item) => item.productId == productId);
    if (existingIndex >= 0) {
      _items[existingIndex] = _items[existingIndex].copyWith(
        quantity: _items[existingIndex].quantity + 1,
      );
    } else {
      _items.add(InvoiceItem(
        productId: productId,
        productName: product['name_ar'] as String? ?? '',
        unitPrice: MoneyHelper.readMoney(product['sell_price']),
        quantity: 1,
        baseQuantity: 1.0,
      ));
    }
    notifyListeners();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void updateItemQuantity(int index, double quantity) {
    if (index >= 0 && index < _items.length) {
      _items[index] = _items[index].copyWith(quantity: quantity);
      notifyListeners();
    }
  }

  void updateItemPrice(int index, double price) {
    if (index >= 0 && index < _items.length) {
      _items[index] = _items[index].copyWith(unitPrice: price);
      notifyListeners();
    }
  }

  /// Get subtotal before discount.
  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Get total after discount and transport.
  double get total => subtotal - _discount + _transportCharges;

  /// Get total items count.
  int get itemCount => _items.length;

  /// Clear all items and reset state.
  void clear() {
    _items.clear();
    _discount = 0.0;
    _transportCharges = 0.0;
    _selectedCustomerId = null;
    notifyListeners();
  }
}

/// Represents an item in the invoice.
class InvoiceItem {
  final int productId;
  final String productName;
  final double unitPrice;
  final double quantity;
  final double baseQuantity;

  const InvoiceItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.baseQuantity,
  });

  double get totalPrice => unitPrice * quantity;

  InvoiceItem copyWith({
    int? productId,
    String? productName,
    double? unitPrice,
    double? quantity,
    double? baseQuantity,
  }) {
    return InvoiceItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      baseQuantity: baseQuantity ?? this.baseQuantity,
    );
  }
}
