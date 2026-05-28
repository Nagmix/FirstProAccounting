import "package:flutter/scheduler.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/barcode_scanner_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  POS SCREEN – FirstPro Arabic Accounting App
//  Shift-gated, deferred posting, multi-payment, mobile-first
// ═══════════════════════════════════════════════════════════════════════════════

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with TickerProviderStateMixin {
  // ── Search & Barcode ──────────────────────────────────────────────
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;

  // ── Cart state ────────────────────────────────────────────────────
  final List<_CartItem> _cart = [];
  double _orderDiscount = 0;
  DiscountType _discountType = DiscountType.fixed;
  int? _selectedCustomerId;
  String _selectedCustomerName = '';

  // ── Checkout phase (replaces _isCheckingOut + showDialog) ──────────
  // Using a state-based overlay instead of showDialog prevents
  // dialog stacking which caused the multi-click bug.
  _CheckoutPhase _checkoutPhase = _CheckoutPhase.idle;
  String _lastInvoiceId = '';
  double _capturedTotal = 0;
  String _capturedCustomerName = '';
  String _capturedPaymentLabel = '';
  int _capturedCartLength = 0;
  double _capturedSubtotal = 0;
  double _capturedDiscount = 0;
  double _capturedTax = 0;

  // ── Payment state ─────────────────────────────────────────────────
  final List<_PaymentEntry> _payments = [];
  String _activePaymentMethod = 'cash';

  // ── Held orders ───────────────────────────────────────────────────
  final List<_HeldOrder> _heldOrders = [];

  // ── Data from DB ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _categories = [];
  List<Product> _products = [];
  bool _isLoading = true;
  int? _selectedCategoryId;

  // ── Top sellers (today) ───────────────────────────────────────────
  List<Map<String, dynamic>> _topSellers = [];

  // ── Shift state ───────────────────────────────────────────────────
  Map<String, dynamic>? _activeShift;
  String _shiftCashBoxName = '';
  String _cashierName = '';

  // ── Timer for shift duration ──────────────────────────────────────
  late Ticker _ticker;
  Duration _shiftDuration = Duration.zero;

  // ── Draggable sheet controller ────────────────────────────────────
  final _sheetController = DraggableScrollableController();
  double _sheetExtent = 0.12;

  // ── Invoice counter (for readable IDs) ────────────────────────────
  int _todayInvoiceCount = 0;

  // ── Currency (H3: dynamic instead of hardcoded YER) ───────────────
  String _selectedCurrency = 'YER';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  void _onTick(Duration elapsed) {
    if (_activeShift != null && _activeShift!['opened_at'] != null) {
      final opened = DateTime.parse(_activeShift!['opened_at'].toString());
      if (mounted) {
        setState(() => _shiftDuration = DateTime.now().difference(opened));
      }
    }
  }

  void _onSearchChanged() {
    final text = _searchController.text;
    // Auto-detect barcode: if text matches typical barcode pattern, auto-add
    if (text.length >= 4 && !_isSearching) {
      _isSearching = true;
      _tryBarcodeMatch(text);
    }
  }

  Future<void> _tryBarcodeMatch(String barcode) async {
    // 1. Check direct product barcode
    final match = _products.where(
      (p) => (p.barcode ?? '').trim() == barcode.trim(),
    );
    if (match.isNotEmpty) {
      _addToCartWithUnit(match.first);
      _searchController.clear();
      _isSearching = false;
      setState(() {});
      return;
    }

    // 2. Check unit conversion barcodes
    final db = DatabaseHelper();
    final conversion = await db.findUnitConversionByBarcode(barcode);
    if (conversion != null) {
      final productId = conversion['product_id'] as int;
      final product = _products.where((p) => p.id == productId).firstOrNull;
      if (product != null) {
        _addToCartDirect(product, {
          'unit_name': conversion['from_unit'] as String,
          'sell_price': MoneyHelper.readMoney(conversion['sell_price'], fallback: product.sellPrice),
          'conversion_factor': (conversion['conversion_factor'] as num?)?.toDouble() ?? 1.0,
          'barcode': conversion['barcode'] as String?,
        });
        _searchController.clear();
      }
    }

    _isSearching = false;
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sheetController.dispose();
    _ticker.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final catMaps = await db.getAllCategories();
    final prodMaps = await db.getAllProducts(activeOnly: true);

    // Load default cashier name from settings
    final savedName = await db.getSetting('user_name');

    // C7: Query DB for today's POS invoice count to avoid ID collisions after restart
    // IMPORTANT: Date format must match _generateInvoiceId() — NO hyphens!
    final today = DateTime.now();
    final todayStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final count = await db.getTodayPosInvoiceCount(todayStr);

    // Filter products that are sellable and shown in POS
    final posProducts = prodMaps
        .map((m) => Product.fromMap(m))
        .where((p) => p.isSellable && p.showInPos)
        .toList();

    if (mounted) {
      setState(() {
        _categories = catMaps;
        _products = posProducts;
        _isLoading = false;
        _todayInvoiceCount = count;
        if (savedName != null && savedName.isNotEmpty) {
          _cashierName = savedName;
        }
      });
    }
    await _loadActiveShift();
    await _loadHeldOrdersFromDb();
    await _loadTopSellers();
  }

  Future<void> _loadHeldOrdersFromDb() async {
    try {
      final db = DatabaseHelper();
      final dbOrders = await db.getHeldOrders(shiftId: _activeShift?['id']);
      for (final row in dbOrders) {
        final cartData = jsonDecode(row['cart_data'] as String) as List;
        final paymentsData = jsonDecode(row['payments_data'] as String) as List;
        final cartItems = cartData.map((item) => _CartItem(
          productId: item['productId'] as int,
          name: item['productName'] as String,
          quantity: (item['quantity'] as num).toInt(),
          unitPrice: MoneyHelper.readMoney(item['unitPrice']),
          unitName: item['unitName'] as String? ?? 'قطعة',
          conversionFactor: (item['conversionFactor'] as num?)?.toDouble() ?? 1.0, // conversion_factor is non-monetary
        )).toList();
        final payments = paymentsData.map((p) => _PaymentEntry(
          amount: MoneyHelper.readMoney(p['amount']),
          method: p['method'] as String? ?? 'cash',
        )).toList();
        final discountTypeStr = row['discount_type'] as String? ?? 'fixed';
        _heldOrders.add(_HeldOrder(
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
      if (_heldOrders.isNotEmpty && mounted) setState(() {});
    } catch (e) {
      debugPrint('Warning: Could not load held orders from DB: $e');
    }
  }

  Future<void> _loadActiveShift() async {
    final db = DatabaseHelper();
    final cashBoxes = await db.getAllCashBoxes();
    for (final cb in cashBoxes) {
      final shift = await db.getActiveShift(cb['id'] as int);
      if (shift != null) {
        setState(() {
          _activeShift = shift;
          _shiftCashBoxName = (cb['name'] ?? '').toString();
          if (shift['cashier_name'] != null) {
            _cashierName = shift['cashier_name'].toString();
          }
          // H3: Initialize currency from active shift (or cash box)
          _selectedCurrency = (shift['currency'] ?? cb['currency'] ?? 'YER').toString();
        });
        if (!_ticker.isActive) _ticker.start();
        return;
      }
    }
    setState(() {
      _activeShift = null;
      _shiftCashBoxName = '';
      _shiftDuration = Duration.zero;
    });
    if (_ticker.isActive) _ticker.stop();
  }

  Future<void> _loadTopSellers() async {
    final db = DatabaseHelper();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final dbInstance = await db.database;
    final result = await dbInstance.rawQuery(
      "SELECT ii.product_id, ii.product_name, SUM(ii.quantity) AS total_qty "
      "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id = i.id "
      "WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 AND i.created_at LIKE ? "
      "GROUP BY ii.product_id ORDER BY total_qty DESC LIMIT 5",
      ['$todayStr%'],
    );
    if (mounted) {
      setState(() => _topSellers = result);
    }
  }

  /// Refresh product list to update stock badges after sales
  Future<void> _refreshProducts() async {
    final db = DatabaseHelper();
    final prodMaps = await db.getAllProducts(activeOnly: true);
    if (mounted) {
      setState(() {
        _products = prodMaps.map((m) => Product.fromMap(m)).toList();
      });
    }
  }

  // ── Computed properties ───────────────────────────────────────────
  List<Product> get _filteredProducts {
    var result = _products;
    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      result = result.where((p) =>
          p.nameAr.contains(q) ||
          p.nameEn.toLowerCase().contains(q) ||
          (p.barcode ?? '').contains(q)).toList();
    }
    return result;
  }

  double get _subtotal => _cart.fold(0.0, (sum, i) => sum + i.total);

  double get _effectiveDiscount {
    if (_discountType == DiscountType.percentage) {
      return _subtotal * (_orderDiscount / 100);
    }
    return _orderDiscount;
  }

  double get _tax => (_subtotal - _effectiveDiscount) * (AppConstants.defaultVatRate / 100);
  double get _total => _subtotal - _effectiveDiscount + _tax;

  double get _totalPaid => _payments.fold(0.0, (sum, p) => sum + p.amount);
  double get _remaining => _total - _totalPaid;

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Generate readable invoice ID: POS-YYYYMMDD-NNNN
  /// Generate invoice ID using DB-based sequence (no gaps)
  /// Uses getNextInvoiceSequence for gap-free numbering
  Future<String> _generateInvoiceId() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final db = DatabaseHelper();
    final nextSeq = await db.getNextInvoiceSequence('POS-$dateStr', 'pos');
    _todayInvoiceCount = nextSeq;
    final seq = nextSeq.toString().padLeft(4, '0');
    return 'POS-$dateStr-$seq';
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Main content: product grid
                  // AbsorbPointer prevents taps from leaking through
                  // to main content when a checkout overlay is active.
                  AbsorbPointer(
                    absorbing: _checkoutPhase != _CheckoutPhase.idle,
                    child: Column(
                      children: [
                        if (_activeShift != null) _buildShiftInfoBar(),
                        _buildSearchBar(),
                        _buildCategoryChips(),
                        if (_topSellers.isNotEmpty) _buildTopSellers(),
                        Expanded(child: _buildProductGrid()),
                      ],
                    ),
                  ),
                  // Draggable cart sheet at bottom
                  // Positioned at bottom to prevent intercepting taps on product grid
                  if (_activeShift != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      top: 0,
                      child: AbsorbPointer(
                        absorbing: _checkoutPhase != _CheckoutPhase.idle,
                        child: _buildDraggableCartSheet(),
                      ),
                    ),
                  // Shift overlay when no active shift
                  if (_activeShift == null) _buildShiftOverlay(),
                  // ── Checkout overlays (replaces showDialog) ────────
                  // State-based overlays eliminate dialog stacking bug.
                  // Each overlay uses GestureDetector to absorb ALL taps
                  // (including on the transparent background), preventing
                  // any tap-through to widgets below.
                  if (_checkoutPhase == _CheckoutPhase.confirming)
                    _buildCheckoutConfirmationOverlay(),
                  if (_checkoutPhase == _CheckoutPhase.completed)
                    _buildCheckoutCompletedOverlay(),
                ],
              ),
        floatingActionButton: _activeShift != null
            ? FloatingActionButton(
                onPressed: _checkoutPhase != _CheckoutPhase.idle ? null : _scanBarcode,
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                tooltip: 'مسح باركود',
                child: const Icon(Icons.qr_code),
              )
            : null,
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront, size: 22),
          const SizedBox(width: 8),
          const Text('نقطة البيع', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      actions: [
        // H3: Currency selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCurrency,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
              borderRadius: BorderRadius.circular(8),
              items: const [
                DropdownMenuItem(value: 'YER', child: Text('YER')),
                DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedCurrency = val);
              },
            ),
          ),
        ),
        // X-Report
        if (_activeShift != null)
          IconButton(
            onPressed: _showXReport,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'تقرير X',
          ),
        // Z-Report / Close Shift
        if (_activeShift != null)
          IconButton(
            onPressed: _showZReport,
            icon: const Icon(Icons.logout),
            tooltip: 'إغلاق الوردية',
          ),
        // Held orders
        Badge(
          isLabelVisible: _heldOrders.isNotEmpty,
          label: Text('${_heldOrders.length}'),
          child: IconButton(
            onPressed: _showHeldOrders,
            icon: const Icon(Icons.pause_circle),
            tooltip: 'طلبات معلقة',
          ),
        ),
        // Discount
        IconButton(
          onPressed: _cart.isEmpty ? null : _showDiscountDialog,
          icon: const Icon(Icons.label),
          tooltip: 'خصم',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SHIFT OVERLAY (shown when no active shift)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildShiftOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.65),
      child: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 16,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'لا توجد وردية مفتوحة',
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'يجب فتح وردية أولاً قبل إجراء أي عملية بيع',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _showOpenShiftDialog,
                    icon: const Icon(Icons.lock_open, size: 24),
                    label: const Text(
                      'فتح وردية جديدة',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SHIFT INFO BAR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildShiftInfoBar() {
    final shift = _activeShift!;
    final totalSales = MoneyHelper.readMoney(shift['total_sales']);
    final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withOpacity(0.06),
            AppColors.success.withOpacity(0.12),
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        border: Border(
          bottom: BorderSide(
            color: AppColors.success.withOpacity(0.25),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Pulsing dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'وردية مفتوحة',
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 14),

              // Cashier name
              _shiftChip(
                icon: Icons.person,
                label: 'الكاشير',
                value: _cashierName,
              ),
              const SizedBox(width: 10),

              // Duration
              _shiftChip(
                icon: Icons.access_time,
                label: 'المدة',
                value: _formatDuration(_shiftDuration),
              ),
              const SizedBox(width: 10),

              // Cash box
              _shiftChip(
                icon: Icons.account_balance_wallet,
                label: 'الصندوق',
                value: _shiftCashBoxName,
              ),
              const SizedBox(width: 10),

              // Total sales
              _shiftChip(
                icon: Icons.show_chart,
                label: 'المبيعات',
                value: CurrencyFormatter.format(totalSales),
              ),
              const SizedBox(width: 10),

              // Opening amount
              _shiftChip(
                icon: Icons.account_balance_wallet,
                label: 'الافتتاح',
                value: CurrencyFormatter.format(openingAmount),
              ),
              const SizedBox(width: 12),

              // Cash In/Out
              _shiftActionChip(
                label: 'إيداع',
                icon: Icons.arrow_downward,
                color: AppColors.success,
                onTap: () => _showCashInOutDialog(true),
              ),
              const SizedBox(width: 6),
              _shiftActionChip(
                label: 'سحب',
                icon: Icons.arrow_upward,
                color: AppColors.error,
                onTap: () => _showCashInOutDialog(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shiftChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 3),
        Text(
          '$label: ',
          style: context.textTheme.bodySmall?.copyWith(
            color: context.textSecondary,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: context.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _shiftActionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SEARCH BAR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (_) => setState(() {}),
              inputFormatters: [
                // Allow rapid barcode scanner input
                LengthLimitingTextInputFormatter(100),
              ],
              decoration: InputDecoration(
                hintText: 'بحث أو باركود...',
                hintStyle: const TextStyle(fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _scanBarcode,
              icon: const Icon(Icons.qr_code, size: 20),
              label: const Text('مسح'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CATEGORY CHIPS
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        itemCount: _categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _selectedCategoryId == null;
            return FilterChip(
              avatar: const Icon(Icons.grid_view, size: 15),
              label: const Text('الكل'),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategoryId = null),
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
            );
          }
          final cat = _categories[index - 1];
          final isSelected = _selectedCategoryId == cat['id'];
          return FilterChip(
            label: Text(cat['name'] as String),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedCategoryId = cat['id'] as int?),
            selectedColor: AppColors.primary.withOpacity(0.15),
            checkmarkColor: AppColors.primary,
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  TOP SELLERS
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTopSellers() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, size: 16, color: AppColors.warning),
              const SizedBox(width: 4),
              Text(
                'الأكثر مبيعاً',
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _topSellers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final item = _topSellers[index];
                final productName = item['product_name'] as String? ?? '';
                final qty = (item['total_qty'] as num?)?.toInt() ?? 0;
                // Find matching product for tap
                final matchProduct = _products.where((p) => p.id == item['product_id']).firstOrNull;
                return ActionChip(
                  avatar: const Icon(Icons.local_fire_department, size: 14, color: AppColors.warning),
                  label: Text('$productName ($qty)', style: const TextStyle(fontSize: 11)),
                  onPressed: matchProduct != null ? () => _addToCartWithUnit(matchProduct) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PRODUCT GRID
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildProductGrid() {
    final products = _filteredProducts;

    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text('لا توجد منتجات', style: context.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('أضف منتجات من شاشة المنتجات', style: context.textTheme.bodySmall),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 150).floor().clamp(2, 6);
        return RefreshIndicator(
          onRefresh: _loadData,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 120), // bottom padding for cart sheet
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              return _ProductCard(
                product: products[index],
                onTap: () => _addToCartWithUnit(products[index]),
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DRAGGABLE CART SHEET (mobile-first)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildDraggableCartSheet() {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        // Don't rebuild the entire screen on every pixel — just track the extent.
        // The UI reads _sheetExtent inside the DraggableScrollableSheet builder
        // which already rebuilds when the sheet size changes.
        _sheetExtent = notification.extent;
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.12,
        minChildSize: 0.12,
        maxChildSize: 0.88,
        builder: (context, scrollController) {
          final isExpanded = _sheetExtent > 0.5;
          return Container(
            decoration: BoxDecoration(
              color: context.isDarkMode ? AppColors.darkSurface : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                // ── Drag handle ──────────────────────────────────
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // ── Cart header (always visible) ─────────────────
                _buildCartHeader(),

                // ── Cart items (visible when expanded) ──────────
                if (isExpanded) ...[
                  if (_cart.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.shopping_cart,
                              size: 48, color: AppColors.textHint),
                          const SizedBox(height: 8),
                          Text('السلة فارغة', style: context.textTheme.bodyLarge),
                          const SizedBox(height: 4),
                          Text('اضغط على المنتج لإضافته',
                              style: context.textTheme.bodySmall),
                        ],
                      ),
                    )
                  else
                    ..._cart.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return _buildCartItemTile(idx, item);
                    }),

                  const Divider(height: 1),

                  // ── Payment method selector ───────────────────
                  _buildPaymentMethodSelector(),

                  // ── Payment details for active method ────────
                  if (_activePaymentMethod == 'credit')
                    _buildCreditCustomerSelector(),
                  if (_activePaymentMethod == 'ewallet')
                    _buildEwalletFields(),
                  if (_activePaymentMethod == 'bank_transfer')
                    _buildBankTransferFields(),

                  // ── Multi-payment entries ────────────────────
                  if (_payments.isNotEmpty) _buildMultiPaymentSummary(),

                  // ── Totals ──────────────────────────────────
                  _buildTotalsSection(),

                  // ── Action buttons ──────────────────────────
                  _buildActionButtons(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Cart header (always visible at bottom sheet top) ─────────────
  Widget _buildCartHeader() {
    return InkWell(
      onTap: () {
        if (_sheetExtent < 0.5) {
          _sheetController.animateTo(0.88, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        } else {
          _sheetController.animateTo(0.12, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.shopping_cart,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'سلة المشتريات',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_cart.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_cart.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (_cart.isNotEmpty)
              Text(
                CurrencyFormatter.format(_total),
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              _sheetExtent > 0.5
                  ? Icons.arrow_drop_down
                  : Icons.arrow_drop_up,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  // ── Individual cart item tile ────────────────────────────────────
  Widget _buildCartItemTile(int index, _CartItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${CurrencyFormatter.format(item.unitPrice)} × ${item.quantity} ${item.unitName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Quantity controls
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _qtyButton(
                      icon: Icons.remove,
                      onTap: () => _decrementCart(index),
                    ),
                    Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: () => _editQuantity(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _qtyButton(
                      icon: Icons.add,
                      onTap: () => _incrementCart(index),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Total price
              SizedBox(
                width: 70,
                child: Text(
                  CurrencyFormatter.format(item.total),
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),

              // Delete
              IconButton(
                onPressed: () => setState(() => _cart.removeAt(index)),
                icon: const Icon(Icons.delete, size: 16, color: AppColors.error),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 14),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PAYMENT METHOD SELECTOR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildPaymentMethodSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'طريقة الدفع',
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _payMethodChip('نقدي', 'cash', Icons.payments),
              const SizedBox(width: 4),
              _payMethodChip('آجل', 'credit', Icons.access_time),
              const SizedBox(width: 4),
              _payMethodChip('بطاقة', 'card', Icons.credit_card),
              const SizedBox(width: 4),
              _payMethodChip('محفظة', 'ewallet', Icons.account_balance_wallet),
              const SizedBox(width: 4),
              _payMethodChip('تحويل', 'bank_transfer', Icons.business),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payMethodChip(String label, String method, IconData icon) {
    final selected = _activePaymentMethod == method;
    return Expanded(
      child: SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: () => setState(() {
            _activePaymentMethod = method;
            if (method != 'credit') {
              _selectedCustomerId = null;
              _selectedCustomerName = '';
            }
          }),
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? AppColors.primary.withOpacity(0.1) : null,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: selected ? AppColors.primary : null),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Credit customer selector ─────────────────────────────────────
  Widget _buildCreditCustomerSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: _showCustomerSelector,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.info.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(10),
            color: AppColors.info.withOpacity(0.05),
          ),
          child: Row(
            children: [
              const Icon(Icons.person, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Text(
                _selectedCustomerName.isEmpty ? 'اختر العميل' : _selectedCustomerName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _selectedCustomerName.isEmpty ? AppColors.textHint : AppColors.info,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.info),
            ],
          ),
        ),
      ),
    );
  }

  // ── E-Wallet fields ──────────────────────────────────────────────
  Widget _buildEwalletFields() {
    final ewalletPayment = _payments.where((p) => p.method == 'ewallet').firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.secondary.withOpacity(0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, size: 18, color: AppColors.secondary),
                const SizedBox(width: 6),
                Text(
                  'بيانات المحفظة الإلكترونية',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'اسم مزود المحفظة (مثل: فلوسك، جوالي)',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.badge, size: 18),
              ),
              onChanged: (v) {
                // Update the ewallet provider name in payments
                final idx = _payments.indexWhere((p) => p.method == 'ewallet');
                if (idx >= 0) {
                  _payments[idx] = _payments[idx].copyWith(providerName: v);
                }
              },
              controller: TextEditingController(text: ewalletPayment?.providerName ?? '')
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: ewalletPayment?.providerName?.length ?? 0),
                ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage('ewallet'),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('التقاط صورة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickImageFromGallery('ewallet'),
                  icon: const Icon(Icons.image, size: 16),
                  label: const Text('إرفاق صورة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Bank Transfer fields ─────────────────────────────────────────
  Widget _buildBankTransferFields() {
    final bankPayment = _payments.where((p) => p.method == 'bank_transfer').firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.info.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.info.withOpacity(0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, size: 18, color: AppColors.info),
                const SizedBox(width: 6),
                Text(
                  'بيانات التحويل البنكي',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'اسم البنك / مزود التحويل',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.account_balance, size: 18),
              ),
              onChanged: (v) {
                final idx = _payments.indexWhere((p) => p.method == 'bank_transfer');
                if (idx >= 0) {
                  _payments[idx] = _payments[idx].copyWith(providerName: v);
                }
              },
              controller: TextEditingController(text: bankPayment?.providerName ?? '')
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: bankPayment?.providerName?.length ?? 0),
                ),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'رقم المرجع / رقم التحويل',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.tag, size: 18),
              ),
              onChanged: (v) {
                final idx = _payments.indexWhere((p) => p.method == 'bank_transfer');
                if (idx >= 0) {
                  _payments[idx] = _payments[idx].copyWith(referenceNumber: v);
                }
              },
              controller: TextEditingController(text: bankPayment?.referenceNumber ?? '')
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: bankPayment?.referenceNumber?.length ?? 0),
                ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage('bank_transfer'),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('التقاط صورة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickImageFromGallery('bank_transfer'),
                  icon: const Icon(Icons.image, size: 16),
                  label: const Text('إرفاق صورة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Image picker helpers ─────────────────────────────────────────
  Future<void> _pickImage(String method) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      final idx = _payments.indexWhere((p) => p.method == method);
      if (idx >= 0) {
        setState(() => _payments[idx] = _payments[idx].copyWith(imagePath: image.path));
      }
    }
  }

  Future<void> _pickImageFromGallery(String method) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final idx = _payments.indexWhere((p) => p.method == method);
      if (idx >= 0) {
        setState(() => _payments[idx] = _payments[idx].copyWith(imagePath: image.path));
      }
    }
  }

  // ── Multi-payment summary ────────────────────────────────────────
  Widget _buildMultiPaymentSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'المدفوعات',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._payments.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            p.method == 'cash'
                                ? Icons.payments
                                : p.method == 'credit'
                                    ? Icons.access_time
                                    : p.method == 'card'
                                        ? Icons.credit_card
                                        : p.method == 'ewallet'
                                            ? Icons.account_balance_wallet
                                            : Icons.business,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _paymentLabel(p.method),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (p.providerName != null && p.providerName!.isNotEmpty) ...[
                            Text(
                              ' (${p.providerName})',
                              style: TextStyle(fontSize: 11, color: context.textSecondary),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            CurrencyFormatter.format(p.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() => _payments.remove(p)),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
            if (_remaining.abs() > 0.01) ...[
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _remaining > 0 ? 'المتبقي' : 'الزيادة',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _remaining > 0 ? AppColors.error : AppColors.success,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(_remaining.abs()),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _remaining > 0 ? AppColors.error : AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'credit':
        return 'آجل';
      case 'card':
        return 'بطاقة';
      case 'ewallet':
        return 'محفظة إلكترونية';
      case 'bank_transfer':
        return 'تحويل بنكي';
      default:
        return method;
    }
  }

  // ── Totals section ───────────────────────────────────────────────
  Widget _buildTotalsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          _totalRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal)),
          if (_effectiveDiscount > 0) ...[
            const SizedBox(height: 3),
            _totalRow(
              'الخصم${_discountType == DiscountType.percentage ? ' (${_orderDiscount.toStringAsFixed(0)}%)' : ''}',
              '- ${CurrencyFormatter.format(_effectiveDiscount)}',
              valueColor: AppColors.error,
            ),
          ],
          if (_tax > 0) ...[
            const SizedBox(height: 3),
            _totalRow(
              'الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)',
              CurrencyFormatter.format(_tax),
            ),
          ],
          const Divider(height: 12),
          _totalRow(
            'الإجمالي',
            CurrencyFormatter.format(_total),
            valueStyle: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {Color? valueColor, TextStyle? valueStyle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium),
        Text(
          value,
          style: valueStyle ??
              context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
        ),
      ],
    );
  }

  // ── Action buttons ───────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      child: Column(
        children: [
          // Add payment button
          if (_cart.isNotEmpty && _payments.isEmpty)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => _addPayment(_activePaymentMethod, _total),
                icon: const Icon(Icons.add, size: 18),
                label: Text('إضافة دفعة: ${_paymentLabel(_activePaymentMethod)}'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          // Add partial payment (multi-payment)
          if (_cart.isNotEmpty && _payments.isNotEmpty && _remaining > 0.01)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () => _showAddPartialPaymentDialog(),
                  icon: const Icon(Icons.add_circle, size: 16),
                  label: const Text('إضافة دفعة أخرى'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Checkout button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_cart.isEmpty || _checkoutPhase != _CheckoutPhase.idle) ? null : _startCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'إنهاء البيع  ${CurrencyFormatter.format(_total)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Hold order button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _cart.isEmpty ? null : _holdOrder,
              icon: const Icon(Icons.pause_circle, size: 18),
              label: const Text('تعليق الطلب'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Clear invoice button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: (_cart.isEmpty || _checkoutPhase != _CheckoutPhase.idle) ? null : () {
                setState(() {
                  _cart.clear();
                  _payments.clear();
                  _orderDiscount = 0;
                  _discountType = DiscountType.fixed;
                  _selectedCustomerId = null;
                  _selectedCustomerName = '';
                  _activePaymentMethod = 'cash';
                  _searchController.clear();
                  _isSearching = false;
                });
                _sheetController.animateTo(0.12,
                    duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('مسح الفاتورة'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  OPEN SHIFT DIALOG
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showOpenShiftDialog() async {
    final db = DatabaseHelper();
    final cashBoxes = await db.getAllCashBoxes();
    if (cashBoxes.isEmpty) {
      if (mounted) {
        context.showErrorSnackBar('لا توجد صناديق نقدية. أضف صندوقاً أولاً من الإعدادات.');
      }
      return;
    }

    int? selectedCashBoxId = cashBoxes.first['id'] as int?;
    final amountController = TextEditingController(text: '0');
    final cashierNameController = TextEditingController(text: _cashierName);
    final notesController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_open, color: AppColors.success, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'فتح وردية جديدة',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Cashier name ─────────────────────────────────
                Text('اسم الكاشير', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: cashierNameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'أدخل اسم الكاشير',
                    prefixIcon: const Icon(Icons.person, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Cash box selector ────────────────────────────
                Text('الصندوق النقدي', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selectedCashBoxId,
                      isExpanded: true,
                      items: cashBoxes.map<DropdownMenuItem<int>>((cb) {
                        final id = cb['id'] as int;
                        final name = cb['name']?.toString() ?? '';
                        final type = cb['type']?.toString() ?? 'cash_box';
                        final currency = cb['currency']?.toString() ?? 'YER';
                        final typeLabel = type == 'bank' ? 'بنك' : 'صندوق';
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text('$name ($typeLabel - $currency)'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) selectedCashBoxId = val;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Opening amount ───────────────────────────────
                Text('مبلغ الافتتاح', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'أدخل مبلغ الافتتاح',
                    suffixText: AppConstants.currency,
                    prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Notes ────────────────────────────────────────
                Text('ملاحظات (اختياري)', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'ملاحظات...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Open shift button ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (selectedCashBoxId == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('اختر صندوقاً نقدیاً'), backgroundColor: AppColors.warning),
                        );
                        return;
                      }
                      if (cashierNameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('أدخل اسم الكاشير'), backgroundColor: AppColors.warning),
                        );
                        return;
                      }

                      final existingShift = await db.getActiveShift(selectedCashBoxId!);
                      if (existingShift != null) {
                        if (mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('يوجد وردية مفتوحة لهذا الصندوق بالفعل'), backgroundColor: AppColors.warning),
                          );
                        }
                        return;
                      }

                      final cashierName = cashierNameController.text.trim();
                      final openingAmount = double.tryParse(amountController.text) ?? 0.0;
                      final now = DateTime.now();

                      // Get next shift number
                      final dbInstance = await db.database;
                      final countResult = await dbInstance.rawQuery(
                        "SELECT COUNT(*) as cnt FROM shifts WHERE date(opened_at) = date(?)",
                        [now.toIso8601String()],
                      );
                      final shiftNum = (countResult.first['cnt'] as int) + 1;

                      final shiftMap = {
                        'shift_number': shiftNum,
                        'cashier_id': null,
                        'cashier_name': cashierName,
                        'cash_box_id': selectedCashBoxId,
                        'opening_amount': openingAmount,
                        'closing_amount': null,
                        'expected_amount': openingAmount,
                        'difference': null,
                        'status': 'open',
                        'opened_at': now.toIso8601String(),
                        'closed_at': null,
                        'notes': notesController.text.isEmpty ? null : notesController.text,
                        'total_sales': 0.0,
                        'total_returns': 0.0,
                        'total_discounts': 0.0,
                        'transaction_count': 0,
                        'currency': _selectedCurrency,
                        'created_at': now.toIso8601String(),
                        'updated_at': now.toIso8601String(),
                      };
                      await db.openShift(shiftMap);

                      // Save cashier name to settings
                      await db.setSetting('user_name', cashierName);

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _cashierName = cashierName;
                      await _loadActiveShift();
                      context.showSuccessSnackBar('تم فتح الوردية $shiftNum بنجاح');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('فتح الوردية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CASH IN / CASH OUT DIALOG
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showCashInOutDialog(bool isCashIn) async {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }

    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isCashIn ? AppColors.success : AppColors.error).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
                      color: isCashIn ? AppColors.success : AppColors.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isCashIn ? 'إيداع نقدي' : 'سحب نقدي',
                    style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('المبلغ', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isCashIn ? 'أدخل مبلغ الإيداع' : 'أدخل مبلغ السحب',
                  suffixText: AppConstants.currency,
                  prefixIcon: Icon(
                    Icons.payments,
                    size: 20,
                    color: isCashIn ? AppColors.success : AppColors.error,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              Text('السبب', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: isCashIn ? 'سبب الإيداع...' : 'سبب السحب...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountController.text) ?? 0.0;
                    if (amount <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('أدخل مبلغاً صحيحاً'), backgroundColor: AppColors.warning),
                      );
                      return;
                    }

                    // Record the cash in/out transaction in the database
                    try {
                      final db = DatabaseHelper();
                      final shiftId = _activeShift!['id'] as int;
                      final cashBoxId = _activeShift!['cash_box_id'] as int;
                      final now = DateTime.now();
                      final dbInstance = await db.database;

                      // Update cash box balance
                      final cashBox = await db.getCashBoxById(cashBoxId);
                      if (cashBox != null) {
                        final currentBalance = MoneyHelper.readMoney(cashBox['balance']);
                        final newBalance = isCashIn
                            ? currentBalance + amount
                            : currentBalance - amount;
                        await dbInstance.update(
                          'cash_boxes',
                          {
                            'balance': newBalance.abs(),
                            'balance_type': newBalance >= 0 ? 'credit' : 'debit',
                            'updated_at': now.toIso8601String(),
                          },
                          where: 'id = ?',
                          whereArgs: [cashBoxId],
                        );
                      }

                      // Create journal entries for the cash in/out
                      final codeOffset = {'YER': 0, 'SAR': 1, 'USD': 2}[_selectedCurrency] ?? 0;
                      final cashAccountCode = 1100 + codeOffset;
                      final cashAccount = await db.getAccountByCodeAndCurrency(
                        cashAccountCode.toString(), _selectedCurrency,
                      );
                      final expenseAccountCode = 5000 + codeOffset;
                      final expenseAccount = await db.getAccountByCodeAndCurrency(
                        expenseAccountCode.toString(), _selectedCurrency,
                      );

                      if (cashAccount != null && expenseAccount != null) {
                        final cashAccountId = cashAccount['id'] as int;
                        final expenseAccountId = expenseAccount['id'] as int;
                        final reason = reasonController.text.trim().isNotEmpty
                            ? reasonController.text.trim()
                            : (isCashIn ? 'إيداع نقدي في الوردية' : 'سحب نقدي من الوردية');

                        // Journal entry: Debit and Credit
                        if (isCashIn) {
                          // إيداع: مدين (الصندوق) / دائن (مصاريف متنوعة)
                          await dbInstance.insert('transactions', {
                            'account_id': cashAccountId,
                            'debit': amount,
                            'credit': 0.0,
                            'description': reason,
                            'date': now.toIso8601String(),
                            'created_at': now.toIso8601String(),
                          });
                          await dbInstance.insert('transactions', {
                            'account_id': expenseAccountId,
                            'debit': 0.0,
                            'credit': amount,
                            'description': reason,
                            'date': now.toIso8601String(),
                            'created_at': now.toIso8601String(),
                          });
                          // Update account balances
                          await db.updateAccountBalance(cashAccountId, amount, isDebit: true);
                          await db.updateAccountBalance(expenseAccountId, amount, isDebit: false);
                        } else {
                          // سحب: مدين (مصاريف متنوعة) / دائن (الصندوق)
                          await dbInstance.insert('transactions', {
                            'account_id': expenseAccountId,
                            'debit': amount,
                            'credit': 0.0,
                            'description': reason,
                            'date': now.toIso8601String(),
                            'created_at': now.toIso8601String(),
                          });
                          await dbInstance.insert('transactions', {
                            'account_id': cashAccountId,
                            'debit': 0.0,
                            'credit': amount,
                            'description': reason,
                            'date': now.toIso8601String(),
                            'created_at': now.toIso8601String(),
                          });
                          // Update account balances
                          await db.updateAccountBalance(expenseAccountId, amount, isDebit: true);
                          await db.updateAccountBalance(cashAccountId, amount, isDebit: false);
                        }
                      }

                      // Update shift totals — cash in/out are operational, not sales/discounts
                      if (isCashIn) {
                        await dbInstance.update(
                          'shifts',
                          {
                            'transaction_count': ((_activeShift!['transaction_count'] as int?) ?? 0) + 1,
                            'updated_at': now.toIso8601String(),
                          },
                          where: 'id = ?',
                          whereArgs: [shiftId],
                        );
                      } else {
                        await dbInstance.update(
                          'shifts',
                          {
                            'transaction_count': ((_activeShift!['transaction_count'] as int?) ?? 0) + 1,
                            'updated_at': now.toIso8601String(),
                          },
                          where: 'id = ?',
                          whereArgs: [shiftId],
                        );
                      }

                      // Refresh shift data
                      await _loadActiveShift();

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      context.showSuccessSnackBar(
                        isCashIn
                            ? 'تم الإيداع بنجاح: ${CurrencyFormatter.format(amount)}'
                            : 'تم السحب بنجاح: ${CurrencyFormatter.format(amount)}',
                      );
                    } catch (e) {
                      if (mounted) {
                        context.showErrorSnackBar('حدث خطأ أثناء تسجيل العملية');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCashIn ? AppColors.success : AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    isCashIn ? 'تأكيد الإيداع' : 'تأكيد السحب',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  X-REPORT (Mid-Shift Report)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showXReport() async {
    if (_activeShift == null) return;

    final shift = _activeShift!;
    final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);
    final totalSales = MoneyHelper.readMoney(shift['total_sales']);
    final totalReturns = MoneyHelper.readMoney(shift['total_returns']);
    final totalDiscounts = MoneyHelper.readMoney(shift['total_discounts']);
    final transactionCount = (shift['transaction_count'] as num?)?.toInt() ?? 0;
    final expectedAmount = openingAmount + totalSales - totalReturns - totalDiscounts;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bar_chart, color: AppColors.info, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'تقرير X – منتصف الوردية',
                    style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _reportRow('رقم الوردية', shift['shift_number']?.toString() ?? '-'),
              _reportRow('الكاشير', _cashierName),
              _reportRow('الصندوق', _shiftCashBoxName),
              _reportRow('المدة', _formatDuration(_shiftDuration)),
              const Divider(height: 24),
              _reportRow('رصيد الافتتاح', CurrencyFormatter.format(openingAmount), valueColor: AppColors.primary),
              _reportRow('إجمالي المبيعات', CurrencyFormatter.format(totalSales), valueColor: AppColors.success),
              _reportRow('إجمالي المرتجعات', CurrencyFormatter.format(totalReturns), valueColor: AppColors.error),
              _reportRow('إجمالي الخصومات', CurrencyFormatter.format(totalDiscounts), valueColor: AppColors.warning),
              const Divider(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    _reportRow('المتوقع في الصندوق', CurrencyFormatter.format(expectedAmount),
                        valueColor: AppColors.primary, isBold: true),
                    const SizedBox(height: 6),
                    _reportRow('عدد المعاملات', transactionCount.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('إغلاق التقرير', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Z-REPORT / CLOSE SHIFT (with deferred posting)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showZReport() async {
    if (_activeShift == null) return;

    final shift = _activeShift!;
    final shiftId = shift['id'] as int;
    final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);
    final totalSales = MoneyHelper.readMoney(shift['total_sales']);
    final totalReturns = MoneyHelper.readMoney(shift['total_returns']);
    final totalDiscounts = MoneyHelper.readMoney(shift['total_discounts']);
    final transactionCount = (shift['transaction_count'] as num?)?.toInt() ?? 0;
    final expectedAmount = openingAmount + totalSales - totalReturns - totalDiscounts;

    final closingAmountController = TextEditingController();
    final notesController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.logout, color: AppColors.error, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'تقرير Z – إغلاق الوردية',
                      style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _reportRow('رقم الوردية', shift['shift_number']?.toString() ?? '-'),
                _reportRow('الكاشير', _cashierName),
                _reportRow('الصندوق', _shiftCashBoxName),
                _reportRow('المدة', _formatDuration(_shiftDuration)),
                const Divider(height: 20),

                _reportRow('رصيد الافتتاح', CurrencyFormatter.format(openingAmount)),
                _reportRow('إجمالي المبيعات', CurrencyFormatter.format(totalSales), valueColor: AppColors.success),
                _reportRow('إجمالي المرتجعات', CurrencyFormatter.format(totalReturns), valueColor: AppColors.error),
                _reportRow('إجمالي الخصومات', CurrencyFormatter.format(totalDiscounts), valueColor: AppColors.warning),
                _reportRow('عدد المعاملات', transactionCount.toString()),
                const Divider(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: _reportRow('المتوقع في الصندوق', CurrencyFormatter.format(expectedAmount),
                      valueColor: AppColors.primary, isBold: true),
                ),
                const SizedBox(height: 16),

                Text('المبلغ الفعلي في الصندوق',
                    style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: closingAmountController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'أدخل المبلغ الفعلي',
                    suffixText: AppConstants.currency,
                    prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),

                Text('ملاحظات (اختياري)',
                    style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'ملاحظات الإغلاق...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Close shift button ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final closingAmount =
                          double.tryParse(closingAmountController.text) ?? expectedAmount;
                      final difference = closingAmount - expectedAmount;
                      final now = DateTime.now();
                      final db = DatabaseHelper();

                      // ── Step 1: Post all shift invoices (deferred posting) ──
                      await db.postShiftInvoices(shiftId);

                      // ── Step 2: Close the shift ──
                      final closeData = {
                        'closing_amount': closingAmount,
                        'expected_amount': expectedAmount,
                        'difference': difference,
                        'status': 'closed',
                        'closed_at': now.toIso8601String(),
                        'notes': notesController.text.isEmpty ? shift['notes'] : notesController.text,
                        'updated_at': now.toIso8601String(),
                      };
                      await db.closeShift(shiftId, closeData);

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      await _loadActiveShift();

                      // Show result dialog
                      showDialog(
                        context: context,
                        builder: (dctx) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: AlertDialog(
                            title: Row(
                              children: [
                                Icon(
                                  difference.abs() < 0.005
                                      ? Icons.check_circle
                                      : Icons.warning,
                                  color: difference.abs() < 0.005
                                      ? AppColors.success
                                      : AppColors.warning,
                                  size: 28,
                                ),
                                const SizedBox(width: 8),
                                const Text('تم إغلاق الوردية'),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('المتوقع: ${CurrencyFormatter.format(expectedAmount)}'),
                                Text('الفعلي: ${CurrencyFormatter.format(closingAmount)}'),
                                const SizedBox(height: 8),
                                if (difference.abs() >= 0.005)
                                  Text(
                                    difference > 0
                                        ? 'فائض: ${CurrencyFormatter.format(difference)}'
                                        : 'عجز: ${CurrencyFormatter.format(difference.abs())}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: difference > 0 ? AppColors.success : AppColors.error,
                                    ),
                                  )
                                else
                                  const Text(
                                    'الصندوق متوازن',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                                  ),
                                const SizedBox(height: 8),
                                const Text(
                                  'تم ترحيل جميع فواتير الوردية إلى الحسابات',
                                  style: TextStyle(fontSize: 12, color: AppColors.info),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dctx),
                                child: const Text('حسناً'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('إغلاق الوردية وترحيل الفواتير',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.textSecondary)),
          Text(
            value,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CUSTOMER SELECTOR
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showCustomerSelector() async {
    final db = DatabaseHelper();
    final customers = await db.getAllCustomers();
    final searchController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('اختر العميل',
                  style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث عن عميل...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    var filtered = customers;
                    if (searchController.text.isNotEmpty) {
                      final q = searchController.text.toLowerCase();
                      filtered = customers
                          .where((c) =>
                              (c['name']?.toString() ?? '').toLowerCase().contains(q) ||
                              (c['phone']?.toString() ?? '').contains(q))
                          .toList();
                    }
                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person, size: 48, color: AppColors.textHint),
                            const SizedBox(height: 8),
                            Text('لا يوجد عملاء', style: context.textTheme.bodyLarge),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        final cId = c['id'] as int;
                        final cName = c['name']?.toString() ?? '';
                        final cPhone = c['phone']?.toString() ?? '';
                        final cBalance = MoneyHelper.readMoney(c['balance']);
                        final isSelected = _selectedCustomerId == cId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? AppColors.primary.withOpacity(0.15)
                                : AppColors.surfaceVariant,
                            child: Icon(
                              isSelected ? Icons.check : Icons.person,
                              size: 20,
                              color: isSelected ? AppColors.primary : null,
                            ),
                          ),
                          title: Text(cName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: cPhone.isNotEmpty ? Text(cPhone) : null,
                          trailing: Text(
                            CurrencyFormatter.format(cBalance),
                            style: TextStyle(
                              fontSize: 12,
                              color: cBalance > 0 ? AppColors.error : AppColors.success,
                            ),
                          ),
                          selected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedCustomerId = cId;
                              _selectedCustomerName = cName;
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DISCOUNT DIALOG
  // ═══════════════════════════════════════════════════════════════════
  void _showDiscountDialog() {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    final controller = TextEditingController(
      text: _orderDiscount > 0 ? _orderDiscount.toStringAsFixed(2) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خصم على الطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _discountType == DiscountType.percentage ? 'نسبة الخصم %' : 'مبلغ الخصم',
                  suffixText: _discountType == DiscountType.percentage ? '%' : AppConstants.currency,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('نوع الخصم: '),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('مبلغ ثابت'),
                    selected: _discountType == DiscountType.fixed,
                    onSelected: (_) => setState(() => _discountType = DiscountType.fixed),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('نسبة مئوية'),
                    selected: _discountType == DiscountType.percentage,
                    onSelected: (_) => setState(() => _discountType = DiscountType.percentage),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _orderDiscount = 0);
                Navigator.pop(ctx);
              },
              child: const Text('إزالة الخصم'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text) ?? 0;
                // Validation: discount must be >= 0
                if (value < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الخصم لا يمكن أن يكون سالباً'), backgroundColor: AppColors.error),
                  );
                  return;
                }
                // Validation: fixed discount must not exceed total
                if (_discountType == DiscountType.fixed && value > _subtotal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الخصم لا يمكن أن يتجاوز الإجمالي'), backgroundColor: AppColors.error),
                  );
                  return;
                }
                // Validation: percentage discount must not exceed 100%
                if (_discountType == DiscountType.percentage && value > 100) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('نسبة الخصم لا يمكن أن تتجاوز 100%'), backgroundColor: AppColors.error),
                  );
                  return;
                }
                setState(() {
                  _orderDiscount = value;
                });
                Navigator.pop(ctx);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CART ACTIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Add to cart with unit selection dialog when multiple units exist.
  void _addToCartWithUnit(Product product) async {
    if (_activeShift == null) {
      if (mounted) {
        context.showErrorSnackBar('يجب فتح وردية أولاً');
      }
      return;
    }

    // Guard: product must have an ID
    if (product.id == null) {
      debugPrint('POS: Cannot add product with null ID: ${product.nameAr}');
      if (mounted) {
        context.showErrorSnackBar('خطأ: المنتج غير صالح');
      }
      return;
    }

    final db = DatabaseHelper();
    List<Map<String, dynamic>> availableUnits;
    try {
      availableUnits = await db.getAvailableUnitsForProduct(product.id!);
    } catch (e) {
      debugPrint('Error loading units for product: $e');
      // Fallback: add directly with base unit
      try {
        _addToCartDirect(product, null);
      } catch (e2) {
        debugPrint('POS: Fallback add-to-cart error: $e2');
        if (mounted) {
          context.showErrorSnackBar('خطأ في إضافة المنتج');
        }
      }
      return;
    }

    if (availableUnits.length <= 1) {
      // Only base unit - add directly (backwards compatible)
      try {
        _addToCartDirect(product, availableUnits.isNotEmpty ? availableUnits.first : null);
      } catch (e) {
        debugPrint('POS: Add-to-cart error: $e');
        if (mounted) {
          context.showErrorSnackBar('خطأ في إضافة المنتج');
        }
      }
      return;
    }

    // Multiple units available - show selection dialog
    String? selectedUnitName = availableUnits.first['unit_name'] as String?;
    double selectedPrice = MoneyHelper.readMoney(availableUnits.first['sell_price'], fallback: product.sellPrice);
    double selectedFactor = (availableUnits.first['conversion_factor'] as num?)?.toDouble() ?? 1.0;
    String? selectedBarcode = availableUnits.first['barcode'] as String?;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('اختر الوحدة - ${product.nameAr}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...availableUnits.map((unit) => ListTile(
                  title: Text(unit['unit_name'] as String),
                  subtitle: Text('${CurrencyFormatter.format(MoneyHelper.readMoney(unit['sell_price']))}'),
                  trailing: (unit['unit_name'] == selectedUnitName)
                      ? Icon(Icons.check_circle, color: AppColors.success)
                      : null,
                  onTap: () {
                    setDialogState(() {
                      selectedUnitName = unit['unit_name'] as String;
                      selectedPrice = MoneyHelper.readMoney(unit['sell_price'], fallback: product.sellPrice);
                      selectedFactor = (unit['conversion_factor'] as num?)?.toDouble() ?? 1.0;
                      selectedBarcode = unit['barcode'] as String?;
                    });
                  },
                )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _addToCartDirect(product, {
                    'unit_name': selectedUnitName,
                    'sell_price': selectedPrice,
                    'conversion_factor': selectedFactor,
                    'barcode': selectedBarcode,
                  });
                },
                child: const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add to cart with a specific unit (from dialog or barcode scan).
  void _addToCartDirect(Product product, Map<String, dynamic>? unitInfo) {
    if (_activeShift == null) {
      if (mounted) {
        context.showErrorSnackBar('يجب فتح وردية أولاً');
      }
      return;
    }

    // Guard: product must have an ID
    if (product.id == null) {
      debugPrint('POS: Cannot add product with null ID');
      if (mounted) {
        context.showErrorSnackBar('خطأ: المنتج غير صالح');
      }
      return;
    }

    final factor = (unitInfo?['conversion_factor'] as num?)?.toDouble() ?? 1.0;
    final unitName = (unitInfo?['unit_name'] as String?) ?? 'قطعة';
    final existingIndex = _cart.indexWhere((i) =>
        i.productId == product.id && i.unitName == unitName);
    final requestedQty = existingIndex >= 0 ? _cart[existingIndex].quantity + 1 : 1;

    // Stock check: show warning but always allow adding to cart
    final baseQtyNeeded = requestedQty * factor;
    if (product.currentStock < baseQtyNeeded) {
      if (!product.allowNegative) {
        // Show non-blocking warning but still add product to cart
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تنبيه: المخزون منخفض لـ ${product.nameAr} (${product.currentStock.toInt()})'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        debugPrint('Product ${product.nameAr} allowNegative=true, adding despite zero/negative stock');
      }
    }

    _doAddToCartWithUnit(existingIndex, product, unitInfo);
  }

  /// Internal: actually add the item to cart with unit info.
  void _doAddToCartWithUnit(int existingIndex, Product product, Map<String, dynamic>? unitInfo) {
    if (!mounted) return;

    final unitName = (unitInfo?['unit_name'] as String?) ?? 'قطعة';
    final unitPrice = MoneyHelper.readMoney(unitInfo?['sell_price'], fallback: product.sellPrice);
    final unitBarcode = unitInfo?['barcode'] as String?;
    final factor = (unitInfo?['conversion_factor'] as num?)?.toDouble() ?? 1.0;

    if (existingIndex >= 0) {
      setState(() {
        _cart[existingIndex] = _cart[existingIndex].copyWith(
          quantity: _cart[existingIndex].quantity + 1,
        );
      });
    } else {
      setState(() {
        _cart.add(_CartItem(
          productId: product.id!,
          name: product.nameAr,
          unitPrice: unitPrice,
          quantity: 1,
          unitName: unitName,
          conversionFactor: factor,
          unitBarcode: unitBarcode,
        ));
      });
    }

    // Auto-add a default payment if none exists
    if (_payments.isEmpty && _activePaymentMethod != 'credit') {
      _payments.add(_PaymentEntry(
        method: _activePaymentMethod,
        amount: _total,
      ));
    } else if (_payments.isNotEmpty) {
      // Update the first payment amount if single payment
      if (_payments.length == 1 && _activePaymentMethod != 'credit') {
        _payments[0] = _payments[0].copyWith(amount: _total);
      }
    }

    // Expand cart sheet slightly to show the item
    if (_sheetExtent < 0.3) {
      try {
        _sheetController.animateTo(0.3,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } catch (e) {
        debugPrint('Sheet animation error (non-critical): $e');
      }
    }
  }

  void _addToCart(Product product) {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    // Stock validation – check if enough stock before adding
    final existingIndex = _cart.indexWhere((i) => i.productId == product.id);
    final requestedQty = existingIndex >= 0 ? _cart[existingIndex].quantity + 1 : 1;
    final availableStock = product.currentStock;

    // Show low stock warning but always allow adding to cart
    if (availableStock < requestedQty) {
      if (!product.allowNegative) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تنبيه: المخزون منخفض لـ ${product.nameAr} (${availableStock.toInt()})'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    _doAddToCart(existingIndex, product);
  }

  /// H6: Show low-stock warning dialog; user can proceed or cancel.
  Future<void> _showLowStockWarning(
    Product product,
    int existingIndex,
    int requestedQty,
    double availableStock, {
    Map<String, dynamic>? unitInfo,
  }) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber, color: AppColors.warning),
              const SizedBox(width: 8),
              const Text('تحذير المخزون'),
            ],
          ),
          content: Text(
            'الكمية المتوفرة: ${availableStock.toInt()}، هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );

    if (proceed == true) {
      if (unitInfo != null) {
        _doAddToCartWithUnit(existingIndex, product, unitInfo);
      } else {
        _doAddToCart(existingIndex, product);
      }
    }
  }

  /// Internal: actually add the item to cart (called after optional stock check).
  void _doAddToCart(int existingIndex, Product product) {
    if (existingIndex >= 0) {
      setState(() {
        _cart[existingIndex] = _cart[existingIndex].copyWith(
          quantity: _cart[existingIndex].quantity + 1,
        );
      });
    } else {
      setState(() {
        _cart.add(_CartItem(
          productId: product.id!,
          name: product.nameAr,
          unitPrice: product.sellPrice,
          quantity: 1,
        ));
      });
    }

    // Auto-add a default payment if none exists
    if (_payments.isEmpty && _activePaymentMethod != 'credit') {
      _payments.add(_PaymentEntry(
        method: _activePaymentMethod,
        amount: _total,
      ));
    } else if (_payments.isNotEmpty) {
      // Update the first payment amount if single payment
      if (_payments.length == 1 && _activePaymentMethod != 'credit') {
        _payments[0] = _payments[0].copyWith(amount: _total);
      }
    }

    // Expand cart sheet slightly
    if (_sheetExtent < 0.3) {
      _sheetController.animateTo(0.3,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _incrementCart(int index) {
    setState(() {
      _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity + 1);
    });
    _syncPaymentsWithTotal();
  }

  void _decrementCart(int index) {
    setState(() {
      if (_cart[index].quantity > 1) {
        _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity - 1);
      } else {
        _cart.removeAt(index);
      }
    });
    _syncPaymentsWithTotal();
  }

  /// Allow user to manually enter a quantity via keyboard.
  Future<void> _editQuantity(int index) async {
    final controller = TextEditingController(text: '${_cart[index].quantity}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('الكمية - ${_cart[index].name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'الكمية',
              prefixIcon: Icon(Icons.format_list_numbered),
            ),
            onSubmitted: (v) {
              final qty = int.tryParse(v);
              Navigator.pop(ctx, qty);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(controller.text);
                Navigator.pop(ctx, qty);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (result != null && result > 0) {
      setState(() {
        _cart[index] = _cart[index].copyWith(quantity: result);
      });
      _syncPaymentsWithTotal();
    }
  }

  void _syncPaymentsWithTotal() {
    // If single payment, update the amount
    if (_payments.length == 1 && _activePaymentMethod != 'credit') {
      setState(() {
        _payments[0] = _payments[0].copyWith(amount: _total);
      });
    }
  }

  void _addPayment(String method, double amount) {
    setState(() {
      _payments.add(_PaymentEntry(
        method: method,
        amount: amount,
      ));
    });
  }

  Future<void> _showAddPartialPaymentDialog() async {
    final amountController = TextEditingController();
    String selectedMethod = _activePaymentMethod;

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة دفعة جزئية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedMethod,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                items: [
                  DropdownMenuItem(value: 'cash', child: Text('نقدي - المتبقي: ${CurrencyFormatter.format(_remaining)}')),
                  DropdownMenuItem(value: 'card', child: const Text('بطاقة')),
                  DropdownMenuItem(value: 'ewallet', child: const Text('محفظة إلكترونية')),
                  DropdownMenuItem(value: 'bank_transfer', child: const Text('تحويل بنكي')),
                  DropdownMenuItem(value: 'credit', child: const Text('آجل')),
                ],
                onChanged: (v) => selectedMethod = v ?? 'cash',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'مبلغ الدفعة',
                  suffixText: AppConstants.currency,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount > 0) {
                  _addPayment(selectedMethod, amount);
                }
                Navigator.pop(ctx);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CHECKOUT – State-based overlay (NO showDialog)
  //  ═══════════════════════════════════════════════════════════════════
  //  ROOT CAUSE of multi-click bug: showDialog pushes a route onto the
  //  Navigator. If _checkout() is called again (due to widget rebuilds,
  //  ticker setState, or rapid taps), multiple dialog routes stack up.
  //  Each "تأكيد البيع" click only pops ONE dialog, so N stacked
  //  dialogs require N clicks.
  //
  //  FIX: Replace ALL showDialog calls with state-based overlays that
  //  are part of the widget tree. Only ONE overlay can exist at a time
  //  (controlled by _checkoutPhase enum), making stacking impossible.
  // ═══════════════════════════════════════════════════════════════════

  /// Step 1: Start checkout – capture values and show confirmation overlay
  void _startCheckout() async {
    if (_checkoutPhase != _CheckoutPhase.idle) return;
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً قبل إتمام عملية البيع');
      return;
    }

    final primaryMethod = _payments.isNotEmpty ? _payments.first.method : _activePaymentMethod;

    if (primaryMethod == 'credit' && _selectedCustomerId == null) {
      context.showErrorSnackBar('يجب اختيار عميل للبيع آجل');
      return;
    }

    // ── التحقق من سقف الدين للعميل عند البيع الآجل ──
    if (primaryMethod == 'credit' && _selectedCustomerId != null) {
      final db = DatabaseHelper();
      final isOverCeiling = await db.isCustomerOverDebtCeiling(_selectedCustomerId!, _total);
      if (isOverCeiling) {
        if (mounted) {
          context.showErrorSnackBar('تجاوز سقف الدين! لا يمكن إتمام البيع الآجل لهذا العميل');
        }
        return;
      }
    }

    if (primaryMethod != 'credit' && _totalPaid < _total - 0.01 && _payments.isNotEmpty) {
      context.showErrorSnackBar('المبلغ المدفوع أقل من الإجمالي');
      return;
    }

    // Capture all values BEFORE changing phase
    setState(() {
      _capturedCartLength = _cart.length;
      _capturedSubtotal = _subtotal;
      _capturedDiscount = _effectiveDiscount;
      _capturedTax = _tax;
      _capturedTotal = _total;
      _capturedCustomerName = _selectedCustomerName;
      _capturedPaymentLabel = _paymentLabel(primaryMethod);
      _checkoutPhase = _CheckoutPhase.confirming;
    });
  }

  /// Step 2: User confirmed – save invoice and show completion overlay
  Future<void> _confirmCheckout() async {
    // GUARD: Prevent double-execution from rapid taps.
    // setState is async (rebuild happens next frame), so a second tap
    // could call this method again before the overlay is removed.
    if (_checkoutPhase != _CheckoutPhase.confirming) return;

    final primaryMethod = _payments.isNotEmpty ? _payments.first.method : _activePaymentMethod;

    setState(() => _checkoutPhase = _CheckoutPhase.saving);

    try {
      final invoiceId = await _generateInvoiceId();
      final cashBoxId = _activeShift!['cash_box_id'] as int;
      final shiftId = _activeShift!['id'] as int;
      final now = DateTime.now();

      String paymentMechanism = primaryMethod == 'credit' ? 'credit' : 'cash';
      String paymentMethod = primaryMethod;

      final invoiceMap = {
        'id': invoiceId,
        'type': 'pos',
        'payment_mechanism': paymentMechanism,
        'payment_method': paymentMethod,
        'is_return': 0,
        'cash_box_id': cashBoxId,
        'customer_id': _selectedCustomerId,
        'subtotal': _subtotal,
        'discount_rate': _discountType == DiscountType.percentage
            ? _orderDiscount
            : (_subtotal > 0 ? (_effectiveDiscount / _subtotal) * 100 : 0.0),
        'discount_amount': _effectiveDiscount,
        'tax_amount': _tax,
        'total': _total,
        'paid_amount': primaryMethod == 'credit' ? 0.0 : _total,
        'remaining': primaryMethod == 'credit' ? _total : 0.0,
        'status': primaryMethod == 'credit' ? 'unpaid' : 'paid',
        'cashier_name': _cashierName,
        'shift_id': shiftId,
        'is_posted': 0,
        'currency': _selectedCurrency,
        'created_at': now.toIso8601String(),
      };

      final items = _cart.map((item) => {
        'invoice_id': invoiceId,
        'product_id': item.productId,
        'product_name': item.name,
        'quantity': item.quantity, // Quantity in the selected unit
        'unit_price': item.unitPrice,
        'total_price': item.total,
        'unit_name': item.unitName,
        'conversion_factor': item.conversionFactor,
        'base_quantity': item.baseQuantity, // Always in base unit for stock
      }).toList();

      final db = DatabaseHelper();
      await db.saveInvoiceWithJournalEntries(
        invoiceMap,
        items,
        invoiceType: 'pos',
        paymentMechanism: paymentMechanism,
        isReturn: false,
        cashBoxId: cashBoxId,
        deferPosting: true,
      );

      await db.updateShiftTotals(shiftId, _total, 0.0, _effectiveDiscount);
      await _loadActiveShift();

      if (!mounted) return;

      // Save invoice ID for print and display
      _lastInvoiceId = invoiceId;

      // Reset cart for next invoice
      _resetForNewInvoice();

      // Refresh top sellers and products after successful checkout
      _loadTopSellers();
      _refreshProducts();

      // Show completion overlay
      setState(() => _checkoutPhase = _CheckoutPhase.completed);
    } catch (e) {
      if (mounted) {
        setState(() => _checkoutPhase = _CheckoutPhase.idle);
        context.showErrorSnackBar('حدث خطأ أثناء حفظ الفاتورة');
      }
    }
  }

  /// Cancel checkout – go back to idle
  void _cancelCheckout() {
    setState(() => _checkoutPhase = _CheckoutPhase.idle);
  }

  /// Dismiss completion overlay – go back to idle
  void _dismissCompletion() {
    setState(() => _checkoutPhase = _CheckoutPhase.idle);
  }

  // ── Checkout Confirmation Overlay ──────────────────────────────────
  Widget _buildCheckoutConfirmationOverlay() {
    // GestureDetector with HitTestBehavior.opaque ensures ALL taps
    // are absorbed (even on the transparent background), preventing
    // tap-through to widgets below the overlay.
    return GestureDetector(
      onTap: () {}, // Absorb background taps – do nothing
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shopping_cart_checkout, color: AppColors.primary, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        'تأكيد عملية البيع',
                        style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _reportRow('عدد الأصناف', '$_capturedCartLength'),
                  _reportRow('المجموع الفرعي', CurrencyFormatter.format(_capturedSubtotal)),
                  if (_capturedDiscount > 0)
                    _reportRow('الخصم', '- ${CurrencyFormatter.format(_capturedDiscount)}', valueColor: AppColors.error),
                  if (_capturedTax > 0)
                    _reportRow('الضريبة', CurrencyFormatter.format(_capturedTax)),
                  const Divider(height: 20),
                  _reportRow('الإجمالي', CurrencyFormatter.format(_capturedTotal),
                      valueColor: AppColors.primary, isBold: true),
                  const SizedBox(height: 8),
                  _reportRow('طريقة الدفع', _capturedPaymentLabel),
                  if (_capturedCustomerName.isNotEmpty)
                    _reportRow('العميل', _capturedCustomerName),
                  const SizedBox(height: 6),
                  Text(
                    'سيتم تسجيل الفاتورة وترحيلها عند إغلاق الوردية',
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cancelCheckout,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إلغاء', style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _confirmCheckout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('تأكيد البيع', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Checkout Completed Overlay ─────────────────────────────────────
  Widget _buildCheckoutCompletedOverlay() {
    // GestureDetector with HitTestBehavior.opaque ensures ALL taps
    // are absorbed (even on the transparent background), preventing
    // tap-through to widgets below the overlay.
    return GestureDetector(
      onTap: () {}, // Absorb background taps – do nothing
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.success, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        'تم إنهاء البيع',
                        style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('رقم الفاتورة: $_lastInvoiceId',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('الإجمالي: ${CurrencyFormatter.format(_capturedTotal)}',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('طريقة الدفع: $_capturedPaymentLabel',
                      style: const TextStyle(fontSize: 14)),
                  if (_capturedCustomerName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('العميل: $_capturedCustomerName',
                        style: const TextStyle(fontSize: 14)),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'لم يتم ترحيل الفاتورة بعد – سيتم ترحيلها عند إغلاق الوردية',
                    style: TextStyle(fontSize: 11, color: AppColors.info),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _showPrintOptions(_lastInvoiceId);
                          },
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('طباعه'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _dismissCompletion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إغلاق', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reset all state for a new invoice.
  void _resetForNewInvoice() {
    setState(() {
      _cart.clear();
      _payments.clear();
      _orderDiscount = 0;
      _discountType = DiscountType.fixed;
      _selectedCustomerId = null;
      _selectedCustomerName = '';
      _activePaymentMethod = 'cash';
      _searchController.clear();
      _isSearching = false;
    });
    _sheetController.animateTo(0.12,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  /// Show print options (PDF or Bluetooth thermal).
  void _showPrintOptions(String invoiceId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('خيارات الطباعة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
                  ),
                  title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('مشاركة أو حفظ كملف PDF'),
                  trailing: const Icon(Icons.arrow_back_ios, size: 16),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _printPdfInvoice(invoiceId);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bluetooth, color: AppColors.accentBlue),
                  ),
                  title: const Text('طباعة حرارية بلوتوث', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('طباعة على طابعة حرارية 80mm'),
                  trailing: const Icon(Icons.arrow_back_ios, size: 16),
                  onTap: () {
                    Navigator.pop(ctx);
                    _printBluetoothReceipt(invoiceId);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Print invoice as PDF.
  Future<void> _printPdfInvoice(String invoiceId) async {
    try {
      final db = DatabaseHelper();
      final invoiceData = await db.getInvoiceById(invoiceId);
      if (invoiceData == null) {
        if (mounted) context.showErrorSnackBar('لم يتم العثور على الفاتورة');
        return;
      }
      final itemsData = await db.getInvoiceItems(invoiceId);
      await InvoicePdfGenerator.printInvoice(invoiceData, itemsData);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('حدث خطأ أثناء الطباعة');
    }
  }

  /// Print receipt via Bluetooth thermal printer.
  Future<void> _printBluetoothReceipt(String invoiceId) async {
    final printerService = BluetoothPrinterService.instance;

    if (!printerService.isConnected) {
      final connected = await printerService.autoConnect();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الطابعة غير متصلة. يرجى إعدادها من الإعدادات'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }
    }

    try {
      final currencySymbol = _selectedCurrency == 'SAR' ? 'ر.س' : _selectedCurrency == 'USD' ? r'$' : 'ر.ي';

      await printerService.printReceipt({
        'invoice_number': invoiceId,
        'invoice_type': 'فاتورة نقاط بيع',
        'date': DateTime.now(),
        'customer_name': _selectedCustomerName.isEmpty ? 'بدون عميل' : _selectedCustomerName,
        'items': _cart.map((item) => <String, dynamic>{
          'product_name': item.name,
          'unit_name': item.unitName,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total_price': item.total,
        }).toList(),
        'subtotal': _subtotal,
        'discount': _effectiveDiscount,
        'tax': _tax,
        'total': _total,
        'paid': _total,
        'remaining': 0.0,
        'currency': currencySymbol,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال الفاتورة للطابعة الحرارية'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) {
        context.showErrorSnackBar(e.message);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('حدث خطأ أثناء الطباعة الحرارية');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HELD ORDERS
  // ═══════════════════════════════════════════════════════════════════
  void _holdOrder() async {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    _heldOrders.add(_HeldOrder(
      items: List.from(_cart),
      paymentMethod: _activePaymentMethod,
      payments: List.from(_payments),
      discount: _orderDiscount,
      discountType: _discountType,
      customerId: _selectedCustomerId,
      customerName: _selectedCustomerName,
      createdAt: DateTime.now(),
    ));

    // Persist to database
    try {
      final db = DatabaseHelper();
      final cartJson = _cart.map((item) => {
        'productId': item.productId,
        'productName': item.name,
        'quantity': item.quantity,
        'unitPrice': item.unitPrice,
        'unitName': item.unitName,
        'conversionFactor': item.conversionFactor,
      }).toList();
      final paymentsJson = _payments.map((p) => {
        'amount': p.amount,
        'method': p.method,
      }).toList();
      await db.insertHeldOrder({
        'shift_id': _activeShift?['id'],
        'cart_data': jsonEncode(cartJson),
        'payment_method': _activePaymentMethod,
        'payments_data': jsonEncode(paymentsJson),
        'discount': _orderDiscount,
        'discount_type': _discountType.name,
        'customer_id': _selectedCustomerId,
        'customer_name': _selectedCustomerName,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Could not persist held order to DB: $e');
    }
    setState(() {
      _cart.clear();
      _payments.clear();
      _orderDiscount = 0;
      _selectedCustomerId = null;
      _selectedCustomerName = '';
      _sheetController.animateTo(0.12,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
    context.showSuccessSnackBar('تم تعليق الطلب');
  }

  void _showHeldOrders() {
    if (_heldOrders.isEmpty) {
      context.showSnackBar('لا توجد طلبات معلقة');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الطلبات المعلقة', style: context.textTheme.titleLarge),
              const SizedBox(height: 12),
              ..._heldOrders.asMap().entries.map((entry) {
                final idx = entry.key;
                final order = entry.value;
                final total = order.items.fold(0.0, (s, i) => s + i.total);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondary.withOpacity(0.15),
                    child: Text('${idx + 1}'),
                  ),
                  title: Text(
                    '${order.items.length} صنف – ${CurrencyFormatter.format(total)}',
                  ),
                  subtitle: Text(
                    order.customerName.isNotEmpty ? 'العميل: ${order.customerName}' : 'بدون عميل',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          // Delete from DB if persisted
                          if (order.dbId != null) {
                            DatabaseHelper().deleteHeldOrder(order.dbId!);
                          }
                          setState(() {
                            _cart.clear();
                            _cart.addAll(order.items);
                            _activePaymentMethod = order.paymentMethod;
                            _payments.clear();
                            _payments.addAll(order.payments);
                            _orderDiscount = order.discount;
                            _discountType = order.discountType;
                            _selectedCustomerId = order.customerId;
                            _selectedCustomerName = order.customerName;
                            _heldOrders.removeAt(idx);
                          });
                          Navigator.pop(ctx);
                          _sheetController.animateTo(0.5,
                              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        },
                        icon: const Icon(Icons.refresh,
                            color: AppColors.primary),
                        tooltip: 'استرجاع',
                      ),
                      IconButton(
                        onPressed: () {
                          // Delete from DB if persisted
                          if (order.dbId != null) {
                            DatabaseHelper().deleteHeldOrder(order.dbId!);
                          }
                          setState(() => _heldOrders.removeAt(idx));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.delete, color: AppColors.error),
                        tooltip: 'حذف',
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BARCODE SCANNER
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _scanBarcode() async {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result != null && result.isNotEmpty) {
      // Try direct product barcode match first
      final match = _products.where((p) => (p.barcode ?? '').trim() == result.trim());
      if (match.isNotEmpty) {
        _addToCartWithUnit(match.first);
      } else {
        // Try unit conversion barcode match
        final db = DatabaseHelper();
        final conversion = await db.findUnitConversionByBarcode(result);
        if (conversion != null) {
          final productId = conversion['product_id'] as int;
          final product = _products.where((p) => p.id == productId).firstOrNull;
          if (product != null) {
            _addToCartDirect(product, {
              'unit_name': conversion['from_unit'] as String,
              'sell_price': MoneyHelper.readMoney(conversion['sell_price'], fallback: product.sellPrice),
              'conversion_factor': (conversion['conversion_factor'] as num?)?.toDouble() ?? 1.0,
              'barcode': conversion['barcode'] as String?,
            });
          } else {
            if (mounted) {
              context.showErrorSnackBar('لم يتم العثور على منتج بالباركود: $result');
            }
          }
        } else {
          if (mounted) {
            context.showErrorSnackBar('لم يتم العثور على منتج بالباركود: $result');
          }
        }
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

enum DiscountType { fixed, percentage }

/// Checkout phase enum – controls which overlay is shown.
/// Using a single enum guarantees only ONE phase is active at a time,
/// making it impossible for multiple dialogs to stack up.
enum _CheckoutPhase {
  idle,        // Normal state – no overlay
  confirming,  // Showing confirmation overlay
  saving,      // Saving invoice (no overlay, brief processing)
  completed,   // Showing sale complete overlay
}

class _CartItem {
  final int productId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String unitName;           // e.g., 'كرتون' or 'قطعة'
  final double conversionFactor;   // 1.0 for base unit, 24.0 for carton
  final String? unitBarcode;       // barcode for this specific unit

  _CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.unitName = 'قطعة',
    this.conversionFactor = 1.0,
    this.unitBarcode,
  });

  double get total => unitPrice * quantity;
  /// Equivalent quantity in base units (for stock deduction)
  double get baseQuantity => quantity * conversionFactor;

  _CartItem copyWith({int? quantity}) {
    return _CartItem(
      productId: productId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      unitName: unitName,
      conversionFactor: conversionFactor,
      unitBarcode: unitBarcode,
    );
  }
}

class _PaymentEntry {
  final String method;
  final double amount;
  final String? providerName;
  final String? referenceNumber;
  final String? imagePath;

  _PaymentEntry({
    required this.method,
    required this.amount,
    this.providerName,
    this.referenceNumber,
    this.imagePath,
  });

  _PaymentEntry copyWith({
    double? amount,
    String? providerName,
    String? referenceNumber,
    String? imagePath,
  }) {
    return _PaymentEntry(
      method: method,
      amount: amount ?? this.amount,
      providerName: providerName ?? this.providerName,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}

class _HeldOrder {
  final List<_CartItem> items;
  final String paymentMethod;
  final List<_PaymentEntry> payments;
  final double discount;
  final DiscountType discountType;
  final int? customerId;
  final String customerName;
  final DateTime createdAt;
  final int? dbId; // Database row ID for persistence

  _HeldOrder({
    required this.items,
    required this.paymentMethod,
    required this.payments,
    required this.discount,
    required this.discountType,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
    this.dbId,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PRODUCT CARD WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lowStock = product.currentStock <= product.minStock && product.currentStock > 0;
    final outOfStock = product.currentStock <= 0 && !product.allowNegative;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Product icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),

              // Name
              Text(
                product.nameAr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),

              // Price
              Text(
                CurrencyFormatter.format(product.sellPrice),
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 3),

              // Stock badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: outOfStock
                      ? AppColors.errorLight
                      : lowStock
                          ? AppColors.warningLight
                          : product.currentStock <= 0
                              ? AppColors.warningLight
                              : AppColors.successLight,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  outOfStock
                      ? 'نفذ'
                      : product.currentStock <= 0
                          ? 'مسموح'
                          : lowStock
                              ? 'منخفض'
                              : '${product.currentStock.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? AppColors.error
                        : lowStock || product.currentStock <= 0
                            ? AppColors.warning
                            : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


