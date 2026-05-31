import 'package:flutter/foundation.dart';
import '../../core/di/service_locator.dart';
import '../../data/datasources/database_helper.dart';
import '../../core/utils/money_helper.dart';

/// ViewModel for POS screen — manages cart, products, and checkout logic.
/// Extracted from PosScreen State (H-08).
class PosViewModel extends ChangeNotifier {
  final DatabaseHelper _db = locator<DatabaseHelper>();

  // ── Product state ──
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> get products => _products;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> get categories => _categories;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  int? _selectedCategoryId;
  int? get selectedCategoryId => _selectedCategoryId;

  // ── Cart state ──
  final List<CartItem> _cartItems = [];
  List<CartItem> get cartItems => List.unmodifiable(_cartItems);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Load products and categories from the database.
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _products = await _db.getAllProducts();
      _categories = await _db.getAllCategories();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
      debugPrint('PosViewModel loadData error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Filter products by search query and/or category.
  List<Map<String, dynamic>> get filteredProducts {
    var result = _products.where((p) => p['is_active'] == 1).toList();
    if (_selectedCategoryId != null) {
      result = result.where((p) => p['category_id'] == _selectedCategoryId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((p) {
        final name = (p['name_ar'] as String? ?? '').toLowerCase();
        final code = (p['item_code'] as String? ?? '').toLowerCase();
        final barcode = (p['barcode'] as String? ?? '').toLowerCase();
        return name.contains(query) || code.contains(query) || barcode.contains(query);
      }).toList();
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

  /// Add a product to the cart.
  void addToCart(Map<String, dynamic> product) {
    final productId = product['id'] as int;
    final existingIndex = _cartItems.indexWhere((item) => item.productId == productId);
    if (existingIndex >= 0) {
      _cartItems[existingIndex] = _cartItems[existingIndex].copyWith(
        quantity: _cartItems[existingIndex].quantity + 1,
      );
    } else {
      _cartItems.add(CartItem(
        productId: productId,
        productName: product['name_ar'] as String? ?? '',
        unitPrice: MoneyHelper.readMoney(product['sell_price']),
        quantity: 1,
      ));
    }
    notifyListeners();
  }

  /// Remove an item from the cart.
  void removeFromCart(int index) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems.removeAt(index);
      notifyListeners();
    }
  }

  /// Update quantity of a cart item.
  void updateCartQuantity(int index, double quantity) {
    if (index >= 0 && index < _cartItems.length) {
      if (quantity <= 0) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index] = _cartItems[index].copyWith(quantity: quantity);
      }
      notifyListeners();
    }
  }

  /// Clear the entire cart.
  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }

  /// Get cart subtotal.
  double get subtotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  /// Get cart item count.
  int get itemCount => _cartItems.length;
}

/// Represents an item in the POS cart.
class CartItem {
  final int productId;
  final String productName;
  final double unitPrice;
  final double quantity;

  const CartItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
  });

  double get totalPrice => unitPrice * quantity;

  CartItem copyWith({int? productId, String? productName, double? unitPrice, double? quantity}) {
    return CartItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }
}
