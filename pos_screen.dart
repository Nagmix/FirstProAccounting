import "package:flutter/scheduler.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
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
    final match = _products.where(
      (p) => (p.barcode ?? '').trim() == barcode.trim(),
    );
    if (match.isNotEmpty) {
      _addToCart(match.first);
      _searchController.clear();
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

    setState(() {
      _categories = catMaps;
      _products = prodMaps.map((m) => Product.fromMap(m)).toList();
      _isLoading = false;
      if (savedName != null && savedName.isNotEmpty) {
        _cashierName = savedName;
      }
    });
    await _loadActiveShift();
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
  String _generateInvoiceId() {
    _todayInvoiceCount++;
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seq = _todayInvoiceCount.toString().padLeft(4, '0');
    return 'POS-$dateStr-$seq';
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Main content: product grid
                  Column(
                    children: [
                      if (_activeShift != null) _buildShiftInfoBar(),
                      _buildSearchBar(),
                      _buildCategoryChips(),
                      Expanded(child: _buildProductGrid()),
                    ],
                  ),
                  // Draggable cart sheet at bottom
                  if (_activeShift != null) _buildDraggableCartSheet(),
                  // Shift overlay when no active shift
                  if (_activeShift == null) _buildShiftOverlay(),
                ],
              ),
        floatingActionButton: _activeShift != null
            ? FloatingActionButton(
                onPressed: _scanBarcode,
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                tooltip: 'مسح باركود',
                child: const Icon(PhosphorIconsRegular.barcode),
              )
            : null,
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsRegular.storefront, size: 22),
          const SizedBox(width: 8),
          const Text('نقطة البيع', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      actions: [
        // X-Report
        if (_activeShift != null)
          IconButton(
            onPressed: _showXReport,
            icon: const Icon(PhosphorIconsRegular.chartBar),
            tooltip: 'تقرير X',
          ),
        // Z-Report / Close Shift
        if (_activeShift != null)
          IconButton(
            onPressed: _showZReport,
            icon: const Icon(PhosphorIconsRegular.signOut),
            tooltip: 'إغلاق الوردية',
          ),
        // Held orders
        Badge(
          isLabelVisible: _heldOrders.isNotEmpty,
          label: Text('${_heldOrders.length}'),
          child: IconButton(
            onPressed: _showHeldOrders,
            icon: const Icon(PhosphorIconsRegular.pauseCircle),
            tooltip: 'طلبات معلقة',
          ),
        ),
        // Discount
        IconButton(
          onPressed: _cart.isEmpty ? null : _showDiscountDialog,
          icon: const Icon(PhosphorIconsRegular.tag),
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
      color: Colors.black.withValues(alpha: 0.65),
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
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.warningCircle,
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
                    icon: const Icon(PhosphorIconsFill.lockOpen, size: 24),
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
    final totalSales = (shift['total_sales'] as num?)?.toDouble() ?? 0.0;
    final openingAmount = (shift['opening_amount'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.06),
            AppColors.success.withValues(alpha: 0.12),
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        border: Border(
          bottom: BorderSide(
            color: AppColors.success.withValues(alpha: 0.25),
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
                      color: AppColors.success.withValues(alpha: 0.5),
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
                icon: PhosphorIconsRegular.user,
                label: 'الكاشير',
                value: _cashierName,
              ),
              const SizedBox(width: 10),

              // Duration
              _shiftChip(
                icon: PhosphorIconsRegular.clock,
                label: 'المدة',
                value: _formatDuration(_shiftDuration),
              ),
              const SizedBox(width: 10),

              // Cash box
              _shiftChip(
                icon: PhosphorIconsRegular.wallet,
                label: 'الصندوق',
                value: _shiftCashBoxName,
              ),
              const SizedBox(width: 10),

              // Total sales
              _shiftChip(
                icon: PhosphorIconsRegular.chartLineUp,
                label: 'المبيعات',
                value: CurrencyFormatter.format(totalSales),
              ),
              const SizedBox(width: 10),

              // Opening amount
              _shiftChip(
                icon: PhosphorIconsRegular.vault,
                label: 'الافتتاح',
                value: CurrencyFormatter.format(openingAmount),
              ),
              const SizedBox(width: 12),

              // Cash In/Out
              _shiftActionChip(
                label: 'إيداع',
                icon: PhosphorIconsRegular.arrowDown,
                color: AppColors.success,
                onTap: () => _showCashInOutDialog(true),
              ),
              const SizedBox(width: 6),
              _shiftActionChip(
                label: 'سحب',
                icon: PhosphorIconsRegular.arrowUp,
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
          border: Border.all(color: color.withValues(alpha: 0.4)),
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
                prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
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
              icon: const Icon(PhosphorIconsRegular.barcode, size: 20),
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
              avatar: const Icon(PhosphorIconsRegular.squaresFour, size: 15),
              label: const Text('الكل'),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategoryId = null),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
            );
          }
          final cat = _categories[index - 1];
          final isSelected = _selectedCategoryId == cat['id'];
          return FilterChip(
            label: Text(cat['name'] as String),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedCategoryId = cat['id'] as int?),
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            checkmarkColor: AppColors.primary,
          );
        },
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
            Icon(PhosphorIconsRegular.magnifyingGlass, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text('لا توجد منتجات', style: context.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('أضف منتجات من شاشة المنتجات', style: context.textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 120), // bottom padding for cart sheet
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.75,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          return _ProductCard(
            product: products[index],
            onTap: () => _addToCart(products[index]),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DRAGGABLE CART SHEET (mobile-first)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildDraggableCartSheet() {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        setState(() => _sheetExtent = notification.extent);
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
                  color: Colors.black.withValues(alpha: 0.12),
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
                          Icon(PhosphorIconsRegular.shoppingCart,
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
            Icon(PhosphorIconsRegular.shoppingCart,
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
                  color: AppColors.primary.withValues(alpha: 0.12),
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
                  ? PhosphorIconsRegular.caretDown
                  : PhosphorIconsRegular.caretUp,
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
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
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
                      '${CurrencyFormatter.format(item.unitPrice)} × ${item.quantity}',
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
                      icon: PhosphorIconsRegular.minus,
                      onTap: () => _decrementCart(index),
                    ),
                    Container(
                      width: 32,
                      alignment: Alignment.center,
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    _qtyButton(
                      icon: PhosphorIconsRegular.plus,
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
                icon: const Icon(PhosphorIconsRegular.trash, size: 16, color: AppColors.error),
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
              _payMethodChip('نقدي', 'cash', PhosphorIconsRegular.money),
              const SizedBox(width: 4),
              _payMethodChip('آجل', 'credit', PhosphorIconsRegular.clock),
              const SizedBox(width: 4),
              _payMethodChip('بطاقة', 'card', PhosphorIconsRegular.creditCard),
              const SizedBox(width: 4),
              _payMethodChip('محفظة', 'ewallet', PhosphorIconsRegular.wallet),
              const SizedBox(width: 4),
              _payMethodChip('تحويل', 'bank_transfer', PhosphorIconsRegular.buildings),
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
            backgroundColor: selected ? AppColors.primary.withValues(alpha: 0.1) : null,
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
            border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10),
            color: AppColors.info.withValues(alpha: 0.05),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsRegular.user, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Text(
                _selectedCustomerName.isEmpty ? 'اختر العميل' : _selectedCustomerName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _selectedCustomerName.isEmpty ? AppColors.textHint : AppColors.info,
                ),
              ),
              const Spacer(),
              const Icon(PhosphorIconsRegular.caretDown, size: 16, color: AppColors.info),
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
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.secondary.withValues(alpha: 0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsRegular.wallet, size: 18, color: AppColors.secondary),
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
                prefixIcon: const Icon(PhosphorIconsRegular.identificationCard, size: 18),
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
                  icon: const Icon(PhosphorIconsRegular.camera, size: 16),
                  label: const Text('التقاط صورة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickImageFromGallery('ewallet'),
                  icon: const Icon(PhosphorIconsRegular.image, size: 16),
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
          border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.info.withValues(alpha: 0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsRegular.buildings, size: 18, color: AppColors.info),
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
                prefixIcon: const Icon(PhosphorIconsRegular.bank, size: 18),
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
                prefixIcon: const Icon(PhosphorIconsRegular.hash, size: 18),
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
                  icon: const Icon(PhosphorIconsRegular.camera, size: 16),
                  label: const Text('التقاط صورة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickImageFromGallery('bank_transfer'),
                  icon: const Icon(PhosphorIconsRegular.image, size: 16),
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
          color: AppColors.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsRegular.creditCard, size: 16, color: AppColors.primary),
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
                                ? PhosphorIconsRegular.money
                                : p.method == 'credit'
                                    ? PhosphorIconsRegular.clock
                                    : p.method == 'card'
                                        ? PhosphorIconsRegular.creditCard
                                        : p.method == 'ewallet'
                                            ? PhosphorIconsRegular.wallet
                                            : PhosphorIconsRegular.buildings,
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
                              PhosphorIconsRegular.x,
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
                icon: const Icon(PhosphorIconsRegular.plus, size: 18),
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
                  icon: const Icon(PhosphorIconsRegular.plusCircle, size: 16),
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
              onPressed: _cart.isEmpty ? null : _checkout,
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
                  const Icon(PhosphorIconsFill.checkCircle, size: 20),
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
              icon: const Icon(PhosphorIconsRegular.pauseCircle, size: 18),
              label: const Text('تعليق الطلب'),
              style: OutlinedButton.styleFrom(
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
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(PhosphorIconsFill.lockOpen, color: AppColors.success, size: 24),
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
                    prefixIcon: const Icon(PhosphorIconsRegular.user, size: 20),
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
                    prefixIcon: const Icon(PhosphorIconsRegular.vault, size: 20),
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
                        'currency': 'YER',
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
                      color: (isCashIn ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCashIn ? PhosphorIconsRegular.arrowDown : PhosphorIconsRegular.arrowUp,
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
                    PhosphorIconsRegular.money,
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
                  onPressed: () {
                    final amount = double.tryParse(amountController.text) ?? 0.0;
                    if (amount <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('أدخل مبلغاً صحيحاً'), backgroundColor: AppColors.warning),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    context.showSuccessSnackBar(
                      isCashIn
                          ? 'تم الإيداع بنجاح: ${CurrencyFormatter.format(amount)}'
                          : 'تم السحب بنجاح: ${CurrencyFormatter.format(amount)}',
                    );
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
    final openingAmount = (shift['opening_amount'] as num?)?.toDouble() ?? 0.0;
    final totalSales = (shift['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalReturns = (shift['total_returns'] as num?)?.toDouble() ?? 0.0;
    final totalDiscounts = (shift['total_discounts'] as num?)?.toDouble() ?? 0.0;
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
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(PhosphorIconsRegular.chartBar, color: AppColors.info, size: 24),
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
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
    final openingAmount = (shift['opening_amount'] as num?)?.toDouble() ?? 0.0;
    final totalSales = (shift['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalReturns = (shift['total_returns'] as num?)?.toDouble() ?? 0.0;
    final totalDiscounts = (shift['total_discounts'] as num?)?.toDouble() ?? 0.0;
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
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(PhosphorIconsRegular.signOut, color: AppColors.error, size: 24),
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
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                    prefixIcon: const Icon(PhosphorIconsRegular.vault, size: 20),
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
                                      ? PhosphorIconsFill.checkCircle
                                      : PhosphorIconsRegular.warning,
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
                  prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
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
                            Icon(PhosphorIconsRegular.user, size: 48, color: AppColors.textHint),
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
                        final cBalance = (c['balance'] as num?)?.toDouble() ?? 0.0;
                        final isSelected = _selectedCustomerId == cId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : AppColors.surfaceVariant,
                            child: Icon(
                              isSelected ? PhosphorIconsFill.check : PhosphorIconsRegular.user,
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
                setState(() {
                  _orderDiscount = double.tryParse(controller.text) ?? 0;
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
  void _addToCart(Product product) {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    final existingIndex = _cart.indexWhere((i) => i.productId == product.id);
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
  //  CHECKOUT (Deferred Invoice Posting)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _checkout() async {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً قبل إتمام عملية البيع');
      return;
    }

    // Determine primary payment method
    final primaryMethod = _payments.isNotEmpty ? _payments.first.method : _activePaymentMethod;

    // Validate credit sale has customer
    if (primaryMethod == 'credit' && _selectedCustomerId == null) {
      context.showErrorSnackBar('يجب اختيار عميل للبيع آجل');
      return;
    }

    // Validate payment covers total (for non-credit)
    if (primaryMethod != 'credit' && _totalPaid < _total - 0.01 && _payments.isNotEmpty) {
      context.showErrorSnackBar('المبلغ المدفوع أقل من الإجمالي');
      return;
    }

    // Confirm payment
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد عملية البيع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reportRow('عدد الأصناف', '${_cart.length}'),
              _reportRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal)),
              if (_effectiveDiscount > 0)
                _reportRow('الخصم', '- ${CurrencyFormatter.format(_effectiveDiscount)}', valueColor: AppColors.error),
              if (_tax > 0)
                _reportRow('الضريبة', CurrencyFormatter.format(_tax)),
              const Divider(height: 16),
              _reportRow('الإجمالي', CurrencyFormatter.format(_total),
                  valueColor: AppColors.primary, isBold: true),
              const SizedBox(height: 8),
              _reportRow('طريقة الدفع', _paymentLabel(primaryMethod)),
              if (_selectedCustomerName.isNotEmpty)
                _reportRow('العميل', _selectedCustomerName),
              const SizedBox(height: 4),
              Text(
                'سيتم تسجيل الفاتورة وترحيلها عند إغلاق الوردية',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('تأكيد البيع'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final invoiceId = _generateInvoiceId();
    final isCash = primaryMethod != 'credit';
    final cashBoxId = _activeShift!['cash_box_id'] as int;
    final shiftId = _activeShift!['id'] as int;
    final now = DateTime.now();

    // Build payment_mechanism and payment_method
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
      'discount_amount': _effectiveDiscount,
      'tax_amount': _tax,
      'total': _total,
      'paid_amount': primaryMethod == 'credit' ? 0.0 : _total,
      'remaining': primaryMethod == 'credit' ? _total : 0.0,
      'status': primaryMethod == 'credit' ? 'unpaid' : 'paid',
      'cashier_name': _cashierName,
      'shift_id': shiftId,
      'is_posted': 0, // NOT POSTED YET – deferred posting
      'currency': 'YER',
      'created_at': now.toIso8601String(),
    };

    final items = _cart.map((item) => {
      'invoice_id': invoiceId,
      'product_id': item.productId,
      'product_name': item.name,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'total_price': item.total,
    }).toList();

    final db = DatabaseHelper();
    await db.insertInvoiceWithItems(invoiceMap, items);

    // Update shift totals (sales, discounts, transaction count)
    final saleAmount = _total;
    final discountAmount = _effectiveDiscount;
    await db.updateShiftTotals(shiftId, saleAmount, 0.0, discountAmount);

    // Update product stock
    for (final item in _cart) {
      try {
        final products = await db.getAllProducts(activeOnly: false);
        final match = products.where((p) => p['id'] == item.productId).firstOrNull;
        if (match != null) {
          final currentStock = (match['current_stock'] as num?)?.toDouble() ?? 0.0;
        }
      } catch (_) {
        // Best effort stock update
      }
    }

    // Reload shift data
    await _loadActiveShift();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsFill.checkCircle, color: AppColors.success, size: 28),
              const SizedBox(width: 8),
              const Text('تم إنهاء البيع'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('رقم الفاتورة: $invoiceId'),
              Text('الإجمالي: ${CurrencyFormatter.format(_total)}'),
              Text('طريقة الدفع: ${_paymentLabel(primaryMethod)}'),
              if (_selectedCustomerName.isNotEmpty)
                Text('العميل: $_selectedCustomerName'),
              const SizedBox(height: 8),
              const Text(
                'لم يتم ترحيل الفاتورة بعد – سيتم ترحيلها عند إغلاق الوردية',
                style: TextStyle(fontSize: 11, color: AppColors.info),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _cart.clear();
                  _payments.clear();
                  _orderDiscount = 0;
                  _selectedCustomerId = null;
                  _selectedCustomerName = '';
                  // Reset sheet
                  _sheetController.animateTo(0.12,
                      duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                });
              },
              child: const Text('فاتورة جديدة'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HELD ORDERS
  // ═══════════════════════════════════════════════════════════════════
  void _holdOrder() {
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
                    backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
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
                        icon: const Icon(PhosphorIconsRegular.arrowCounterClockwise,
                            color: AppColors.primary),
                        tooltip: 'استرجاع',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _heldOrders.removeAt(idx));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(PhosphorIconsRegular.trash, color: AppColors.error),
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
      final match = _products.where((p) => (p.barcode ?? '').trim() == result.trim());
      if (match.isNotEmpty) {
        _addToCart(match.first);
      } else {
        if (mounted) {
          context.showErrorSnackBar('لم يتم العثور على منتج بالباركود: $result');
        }
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

enum DiscountType { fixed, percentage }

class _CartItem {
  final int productId;
  final String name;
  final double unitPrice;
  final int quantity;

  _CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  double get total => unitPrice * quantity;

  _CartItem copyWith({int? quantity}) {
    return _CartItem(
      productId: productId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
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

  _HeldOrder({
    required this.items,
    required this.paymentMethod,
    required this.payments,
    required this.discount,
    required this.discountType,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
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
    final outOfStock = product.currentStock <= 0;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
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
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  PhosphorIconsRegular.package,
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
                          : AppColors.successLight,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  outOfStock
                      ? 'نفذ'
                      : lowStock
                          ? 'منخفض'
                          : '${product.currentStock.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? AppColors.error
                        : lowStock
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


