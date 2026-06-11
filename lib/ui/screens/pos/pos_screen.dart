import "package:flutter/scheduler.dart";
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/invoice_pdf_generator.dart';
import 'package:firstpro/core/services/bluetooth_printer_service.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/viewmodels/pos_viewmodel.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/customer_repository.dart';
import 'package:firstpro/data/datasources/services/shift_service.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/ui/widgets/barcode_scanner_screen.dart';
import 'package:firstpro/ui/screens/pos/pos_models.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_product_card.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_cart_item_tile.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_payment_method_selector.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_totals_section.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_action_buttons.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_shift_info_bar.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_ewallet_fields.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_bank_transfer_fields.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_multi_payment_summary.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_checkout_confirmation.dart';
import 'package:firstpro/ui/screens/pos/widgets/pos_checkout_completed.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_open_shift_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_cash_in_out_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_reports_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_customer_selector_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_discount_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_held_orders_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_print_options_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_partial_payment_dialog.dart';
import 'package:firstpro/ui/screens/pos/dialogs/pos_quantity_edit_dialog.dart';

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
  // ── ViewModel (single source of truth) ────────────────────────────
  final _vm = locator<PosViewModel>();

  // ── Search & Barcode ──────────────────────────────────────────────
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;

  // ── Timer for shift duration ──────────────────────────────────────
  late Ticker _ticker;

  // ── Draggable sheet controller ────────────────────────────────────
  final _sheetController = DraggableScrollableController();
  double _sheetExtent = 0.12;

  @override
  void initState() {
    super.initState();
    // ViewModel is factory-registered — no stale state from previous visits.
    _ticker = createTicker(_onTick);
    _searchController.addListener(_onSearchChanged);
    _vm.loadData();
  }

  void _onTick(Duration elapsed) {
    // Only update shift duration every ~1 second to avoid
    // excessive notifyListeners() calls that cause full rebuilds.
    // The ticker fires every frame (~60fps) but we only need
    // second-level precision for the duration display.
    if (elapsed.inSeconds != _lastTickSeconds) {
      _lastTickSeconds = elapsed.inSeconds;
      _vm.updateShiftDuration();
      // Trigger rebuild directly (VM no longer calls notifyListeners
      // from updateShiftDuration to avoid cascading rebuilds).
      if (mounted) setState(() {});
    }
  }

  int _lastTickSeconds = -1;

  void _onSearchChanged() {
    final text = _searchController.text;
    _vm.setSearchQuery(text);
    // Auto-detect barcode: if text matches typical barcode pattern, auto-add
    if (text.length >= 4 && !_isSearching) {
      _isSearching = true;
      _tryBarcodeMatch(text);
    }
  }

  Future<void> _tryBarcodeMatch(String barcode) async {
    final result = await _vm.tryBarcodeMatch(barcode);
    if (result != null) {
      _addToCartWithUnit(result.product, unitInfo: result.unitInfo);
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
    // ViewModel is factory — it will be GC'd with the State.
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => Scaffold(
        appBar: _buildAppBar(),
        body: _vm.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Main content: product grid
                  // AbsorbPointer prevents taps from leaking through
                  // to main content when a checkout overlay is active.
                  AbsorbPointer(
                    absorbing: _vm.checkoutPhase != CheckoutPhase.idle,
                    child: Column(
                      children: [
                        if (_vm.activeShift != null) _buildShiftInfoBar(),
                        _buildSearchBar(),
                        _buildCategoryChips(),
                        if (_vm.topSellers.isNotEmpty) _buildTopSellers(),
                        Expanded(child: _buildProductGrid()),
                      ],
                    ),
                  ),
                  // Draggable cart sheet at bottom
                  // DraggableScrollableSheet must be a direct child of Stack
                  // (not wrapped in Positioned) for correct gesture handling.
                  if (_vm.activeShift != null)
                    AbsorbPointer(
                      absorbing: _vm.checkoutPhase != CheckoutPhase.idle,
                      child: _buildDraggableCartSheet(),
                    ),
                  // Shift overlay when no active shift
                  if (_vm.activeShift == null) _buildShiftOverlay(),
                  // ── Checkout overlays (replaces showDialog) ────────
                  // State-based overlays eliminate dialog stacking bug.
                  // Each overlay uses GestureDetector to absorb ALL taps
                  // (including on the transparent background), preventing
                  // any tap-through to widgets below.
                  if (_vm.checkoutPhase == CheckoutPhase.confirming ||
                      _vm.checkoutPhase == CheckoutPhase.saving)
                    _buildCheckoutConfirmationOverlay(),
                  if (_vm.checkoutPhase == CheckoutPhase.completed)
                    _buildCheckoutCompletedOverlay(),
                ],
              ),
        floatingActionButton: _vm.activeShift != null
            ? FloatingActionButton(
                onPressed: _vm.checkoutPhase != CheckoutPhase.idle
                    ? null
                    : _scanBarcode,
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                tooltip: 'مسح باركود',
                child: const Icon(Icons.qr_code),
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
          const Icon(Icons.storefront, size: 22),
          const SizedBox(width: 8),
          const Text('نقطة البيع',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      actions: [
        // H3: Currency selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _vm.selectedCurrency,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary),
              borderRadius: BorderRadius.circular(8),
              items: CurrencyConstants.currencyOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) {
                if (val != null) _vm.setSelectedCurrency(val);
              },
            ),
          ),
        ),
        // X-Report
        if (_vm.activeShift != null)
          IconButton(
            onPressed: _showXReport,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'تقرير X',
          ),
        // Z-Report / Close Shift
        if (_vm.activeShift != null)
          IconButton(
            onPressed: _showZReport,
            icon: const Icon(Icons.logout),
            tooltip: 'إغلاق الوردية',
          ),
        // Held orders
        Badge(
          isLabelVisible: _vm.heldOrders.isNotEmpty,
          label: Text('${_vm.heldOrders.length}'),
          child: IconButton(
            onPressed: _showHeldOrders,
            icon: const Icon(Icons.pause_circle),
            tooltip: 'طلبات معلقة',
          ),
        ),
        // Discount
        IconButton(
          onPressed: _vm.cartItems.isEmpty ? null : _showDiscountDialog,
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
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
  //  SHIFT INFO BAR (delegates to extracted widget)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildShiftInfoBar() {
    return PosShiftInfoBar(
      vm: _vm,
      onCashIn: () => _showCashInOutDialog(true),
      onCashOut: () => _showCashInOutDialog(false),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
        itemCount: _vm.categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _vm.selectedCategoryId == null;
            return FilterChip(
              avatar: const Icon(Icons.grid_view, size: 15),
              label: const Text('الكل'),
              selected: isSelected,
              onSelected: (_) => _vm.setSelectedCategory(null),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
            );
          }
          final cat = _vm.categories[index - 1];
          final isSelected = _vm.selectedCategoryId == cat['id'];
          return FilterChip(
            label: Text(cat['name'] as String),
            selected: isSelected,
            onSelected: (_) => _vm.setSelectedCategory(cat['id'] as int?),
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
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
              const Icon(Icons.local_fire_department,
                  size: 16, color: AppColors.warning),
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
              itemCount: _vm.topSellers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final item = _vm.topSellers[index];
                final productName = item['product_name'] as String? ?? '';
                final qty = (item['total_qty'] as num?)?.toInt() ?? 0;
                // Find matching product for tap
                final matchProduct = _vm.products
                    .where((p) => p.id == item['product_id'])
                    .firstOrNull;
                return ActionChip(
                  avatar: const Icon(Icons.local_fire_department,
                      size: 14, color: AppColors.warning),
                  label: Text('$productName ($qty)',
                      style: const TextStyle(fontSize: 11)),
                  onPressed: matchProduct != null
                      ? () => _addToCartWithUnit(matchProduct)
                      : null,
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
    final products = _vm.filteredProducts;

    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text('لا توجد منتجات', style: context.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('أضف منتجات من شاشة المنتجات',
                style: context.textTheme.bodySmall),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 150).floor().clamp(2, 6);
        return RefreshIndicator(
          onRefresh: _vm.loadData,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(
                12, 8, 12, 120), // bottom padding for cart sheet
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              return PosProductCard(
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
        snap: true,
        snapSizes: const [0.12, 0.5, 0.88],
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: context.isDarkMode ? AppColors.darkSurface : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
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

                // ── Cart content (always rendered; ListView handles
                //    visibility efficiently via lazy layout) ─────
                if (_vm.cartItems.isEmpty)
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
                else ...[
                  ..._vm.cartItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return PosCartItemTile(
                      name: item.name,
                      unitPrice: item.unitPrice,
                      quantity: item.quantity,
                      unitName: item.unitName,
                      total: item.total,
                      onIncrement: () => _vm.incrementCart(idx),
                      onDecrement: () => _vm.decrementCart(idx),
                      onEditQuantity: () => _editQuantity(idx),
                      onDelete: () => _vm.removeFromCart(idx),
                    );
                  }),
                ],

                const Divider(height: 1),

                // ── Payment method selector ───────────────────
                PosPaymentMethodSelector(
                  activeMethod: _vm.activePaymentMethod,
                  onMethodChanged: (method) {
                    _vm.setActivePaymentMethod(method);
                    if (method != 'credit') {
                      _vm.setSelectedCustomer(null, '');
                    }
                  },
                ),

                // ── Payment details for active method ────────
                if (_vm.activePaymentMethod == 'credit')
                  _buildCreditCustomerSelector(),
                if (_vm.activePaymentMethod == 'ewallet') _buildEwalletFields(),
                if (_vm.activePaymentMethod == 'bank_transfer')
                  _buildBankTransferFields(),

                // ── Multi-payment entries ────────────────────
                if (_vm.payments.isNotEmpty) _buildMultiPaymentSummary(),

                // ── Totals ──────────────────────────────────
                PosTotalsSection(
                  subtotal: _vm.subtotal,
                  discount: _vm.effectiveDiscount,
                  discountType: _vm.discountType,
                  orderDiscount: _vm.orderDiscount,
                  tax: _vm.tax,
                  total: _vm.total,
                  vatRate: _vm.vatRate,
                ),

                // ── Action buttons ──────────────────────────
                PosActionButtons(
                  cartLength: _vm.cartItems.length,
                  total: _vm.total,
                  activePaymentMethod: _vm.activePaymentMethod,
                  paymentsLength: _vm.payments.length,
                  remaining: _vm.remaining,
                  checkoutPhase: _vm.checkoutPhase,
                  paymentLabel: _paymentLabel,
                  onAddPayment: () => _vm.addPayment(PaymentEntry(
                      method: _vm.activePaymentMethod, amount: _vm.total)),
                  onAddPartialPayment: _showAddPartialPaymentDialog,
                  onStartCheckout: _startCheckout,
                  onHoldOrder: _holdOrder,
                  onClearInvoice: () {
                    _vm.resetForNewInvoice();
                    _searchController.clear();
                    _isSearching = false;
                    _sheetController.animateTo(0.12,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut);
                  },
                ),
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
          _sheetController.animateTo(0.88,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        } else {
          _sheetController.animateTo(0.12,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.shopping_cart, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'سلة المشتريات',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_vm.cartItems.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_vm.cartItems.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (_vm.cartItems.isNotEmpty)
              Text(
                CurrencyFormatter.format(_vm.total),
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              _sheetExtent > 0.5 ? Icons.arrow_drop_down : Icons.arrow_drop_up,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
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
              const Icon(Icons.person, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Text(
                _vm.selectedCustomerName.isEmpty
                    ? 'اختر العميل'
                    : _vm.selectedCustomerName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _vm.selectedCustomerName.isEmpty
                      ? AppColors.textHint
                      : AppColors.info,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_drop_down,
                  size: 16, color: AppColors.info),
            ],
          ),
        ),
      ),
    );
  }

  // ── E-Wallet fields (delegates to extracted widget) ──────────────
  Widget _buildEwalletFields() {
    return PosEwalletFields(
      vm: _vm,
      onPickImage: _pickImage,
      onPickImageFromGallery: _pickImageFromGallery,
    );
  }

  // ── Bank Transfer fields (delegates to extracted widget) ──────────
  Widget _buildBankTransferFields() {
    return PosBankTransferFields(
      vm: _vm,
      onPickImage: _pickImage,
      onPickImageFromGallery: _pickImageFromGallery,
    );
  }

  // ── Image picker helpers ─────────────────────────────────────────
  Future<void> _pickImage(String method) async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      final idx = _vm.payments.indexWhere((p) => p.method == method);
      if (idx >= 0) {
        _vm.updatePayment(
            idx, _vm.payments[idx].copyWith(imagePath: image.path));
      }
    }
  }

  Future<void> _pickImageFromGallery(String method) async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final idx = _vm.payments.indexWhere((p) => p.method == method);
      if (idx >= 0) {
        _vm.updatePayment(
            idx, _vm.payments[idx].copyWith(imagePath: image.path));
      }
    }
  }

  // ── Multi-payment summary (delegates to extracted widget) ────────
  Widget _buildMultiPaymentSummary() {
    return PosMultiPaymentSummary(
      vm: _vm,
      onRemovePayment: () {},
      paymentLabel: _paymentLabel,
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

  // ═══════════════════════════════════════════════════════════════════
  //  OPEN SHIFT DIALOG (delegates to extracted dialog)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showOpenShiftDialog() async {
    await showOpenShiftDialog(context, _vm);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CASH IN / CASH OUT DIALOG (delegates to extracted dialog)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showCashInOutDialog(bool isCashIn) async {
    await showCashInOutDialog(context, _vm, isCashIn);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  X-REPORT (delegates to extracted dialog)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showXReport() async {
    await showXReport(context, _vm);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Z-REPORT / CLOSE SHIFT (delegates to extracted dialog)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showZReport() async {
    await showZReport(context, _vm);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CUSTOMER SELECTOR (delegates to extracted dialog)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _showCustomerSelector() async {
    await showCustomerSelectorDialog(context, _vm);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DISCOUNT DIALOG (delegates to extracted dialog)
  // ═══════════════════════════════════════════════════════════════════
  void _showDiscountDialog() {
    showDiscountDialog(context, _vm);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CART ACTIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Add to cart with unit selection dialog when multiple units exist.
  void _addToCartWithUnit(Product product,
      {Map<String, dynamic>? unitInfo}) async {
    if (_vm.activeShift == null) {
      if (mounted) {
        context.showErrorSnackBar('يجب فتح وردية أولاً');
      }
      return;
    }

    // Guard: product must have an ID
    if (product.id == null) {
      if (mounted) {
        context.showErrorSnackBar('خطأ: المنتج غير صالح');
      }
      return;
    }

    // If unitInfo was provided (e.g., from barcode), add directly
    if (unitInfo != null) {
      _addToCartDirect(product, unitInfo);
      return;
    }

    List<Map<String, dynamic>> availableUnits;
    try {
      availableUnits = await _vm.getAvailableUnitsForProduct(product.id!) ?? [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading units for product: $e');
      }
      // Fallback: add directly with base unit
      try {
        _addToCartDirect(product, null);
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('POS: Fallback add-to-cart error: $e2');
        }
        if (mounted) {
          context.showErrorSnackBar('خطأ في إضافة المنتج');
        }
      }
      return;
    }

    if (!mounted) return;
    if (availableUnits.length <= 1) {
      // Only base unit - add directly (backwards compatible)
      try {
        _addToCartDirect(
            product, availableUnits.isNotEmpty ? availableUnits.first : null);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('POS: Add-to-cart error: $e');
        }
        if (mounted) {
          context.showErrorSnackBar('خطأ في إضافة المنتج');
        }
      }
      return;
    }

    // Multiple units available - show selection dialog
    // Note: getAvailableUnitsForProduct already converts cents to doubles
    String? selectedUnitName = availableUnits.first['unit_name'] as String?;
    double selectedPrice =
        (availableUnits.first['sell_price'] as num?)?.toDouble() ??
            product.sellPrice;
    double selectedFactor =
        (availableUnits.first['conversion_factor'] as num?)?.toDouble() ?? 1.0;
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
                      subtitle: Text(
                          '${CurrencyFormatter.format((unit['sell_price'] as num?)?.toDouble() ?? 0.0)}'),
                      trailing: (unit['unit_name'] == selectedUnitName)
                          ? Icon(Icons.check_circle, color: AppColors.success)
                          : null,
                      onTap: () {
                        setDialogState(() {
                          selectedUnitName = unit['unit_name'] as String;
                          selectedPrice =
                              (unit['sell_price'] as num?)?.toDouble() ??
                                  product.sellPrice;
                          selectedFactor =
                              (unit['conversion_factor'] as num?)?.toDouble() ??
                                  1.0;
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
    if (_vm.activeShift == null) {
      if (mounted) {
        context.showErrorSnackBar('يجب فتح وردية أولاً');
      }
      return;
    }

    // Guard: product must have an ID
    if (product.id == null) {
      if (mounted) {
        context.showErrorSnackBar('خطأ: المنتج غير صالح');
      }
      return;
    }

    final factor = (unitInfo?['conversion_factor'] as num?)?.toDouble() ?? 1.0;
    final unitName = (unitInfo?['unit_name'] as String?) ?? 'قطعة';
    final existingIndex = _vm.cartItems
        .indexWhere((i) => i.productId == product.id && i.unitName == unitName);
    final requestedQty =
        existingIndex >= 0 ? _vm.cartItems[existingIndex].quantity + 1 : 1;

    // Stock check: show warning but always allow adding to cart
    final baseQtyNeeded = requestedQty * factor;
    if (product.currentStock < baseQtyNeeded) {
      if (!product.allowNegative) {
        // Show non-blocking warning but still add product to cart
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'تنبيه: المخزون منخفض لـ ${product.nameAr} (${product.currentStock.toInt()})'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // allowNegative=true, adding despite zero/negative stock
      }
    }

    _vm.addToCartDirect(product, unitInfo);

    // Expand cart sheet to show the item and action buttons
    if (_sheetExtent < 0.5) {
      try {
        _sheetController.animateTo(0.5,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Sheet animation error (non-critical): $e');
        }
      }
    }
  }

  /// Edit quantity for a cart item (delegates to extracted dialog)
  void _editQuantity(int index) async {
    await showEditQuantityDialog(context, _vm, index);
  }

  // Removed _syncPaymentsWithTotal – VM handles payment sync internally.
  // Removed _addPayment – use _vm.addPayment() directly.

  /// Add partial payment (delegates to extracted dialog)
  Future<void> _showAddPartialPaymentDialog() async {
    await showAddPartialPaymentDialog(context, _vm);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CHECKOUT – State-based overlay (NO showDialog)
  // ═══════════════════════════════════════════════════════════════════

  /// Step 1: Start checkout – capture values and show confirmation overlay
  void _startCheckout() async {
    if (_vm.checkoutPhase != CheckoutPhase.idle) return;
    if (_vm.activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً قبل إتمام عملية البيع');
      return;
    }

    final primaryMethod = _vm.payments.isNotEmpty
        ? _vm.payments.first.method
        : _vm.activePaymentMethod;

    if (primaryMethod == 'credit' && _vm.selectedCustomerId == null) {
      context.showErrorSnackBar('يجب اختيار عميل للبيع آجل');
      return;
    }

    // ── التحقق من سقف الدين للعميل عند البيع الآجل ──
    if (primaryMethod == 'credit' && _vm.selectedCustomerId != null) {
      final isOverCeiling = await locator<CustomerRepository>()
          .isCustomerOverDebtCeiling(_vm.selectedCustomerId!, _vm.total,
              currency: _vm.selectedCurrency);
      if (!mounted) return;
      if (isOverCeiling) {
        context.showErrorSnackBar(
            'تجاوز سقف الدين! لا يمكن إتمام البيع الآجل لهذا العميل');
        return;
      }
    }

    if (primaryMethod != 'credit' &&
        _vm.totalPaid < _vm.total - 0.01 &&
        _vm.payments.isNotEmpty) {
      context.showErrorSnackBar('المبلغ المدفوع أقل من الإجمالي');
      return;
    }

    // Capture all values BEFORE changing phase
    _vm.captureCheckoutSnapshot();
    _vm.setCheckoutPhase(CheckoutPhase.confirming);
  }

  /// Step 2: User confirmed – save invoice and show completion overlay
  Future<void> _confirmCheckout() async {
    // GUARD: Prevent double-execution from rapid taps.
    if (_vm.checkoutPhase != CheckoutPhase.confirming) return;

    final primaryMethod = _vm.payments.isNotEmpty
        ? _vm.payments.first.method
        : _vm.activePaymentMethod;

    _vm.setCheckoutPhase(CheckoutPhase.saving);

    try {
      final invoiceId = await _vm.generateInvoiceId();
      final cashBoxId = _vm.activeShift!['cash_box_id'] as int;
      final shiftId = _vm.activeShift!['id'] as int;
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
        'customer_id': _vm.selectedCustomerId,
        'subtotal': _vm.subtotal,
        'discount_rate': _vm.discountType == DiscountType.percentage
            ? _vm.orderDiscount
            : (_vm.subtotal > 0
                ? (_vm.effectiveDiscount / _vm.subtotal) * 100
                : 0.0),
        'discount_amount': _vm.effectiveDiscount,
        'tax_amount': _vm.tax,
        'total': _vm.total,
        'paid_amount': primaryMethod == 'credit' ? 0.0 : _vm.total,
        'remaining': primaryMethod == 'credit' ? _vm.total : 0.0,
        'status': primaryMethod == 'credit' ? 'unpaid' : 'paid',
        'cashier_name': _vm.cashierName,
        'shift_id': shiftId,
        'is_posted': 0,
        'currency': _vm.selectedCurrency,
        'exchange_rate': _vm.exchangeRate,
        'created_at': now.toIso8601String(),
      };

      final items = _vm.cartItems
          .map((item) => {
                'invoice_id': invoiceId,
                'product_id': item.productId,
                'product_name': item.name,
                'quantity': item.quantity, // Quantity in the selected unit
                'unit_price': item.unitPrice,
                'total_price': item.total,
                'unit_name': item.unitName,
                'conversion_factor': item.conversionFactor,
                'base_quantity':
                    item.baseQuantity, // Always in base unit for stock
              })
          .toList();

      await locator<InvoiceRepository>().saveInvoiceWithJournalEntries(
        invoiceMap,
        items,
        invoiceType: 'pos',
        paymentMechanism: paymentMechanism,
        isReturn: false,
        cashBoxId: cashBoxId,
        deferPosting: true,
      );

      await locator<ShiftService>()
          .updateShiftTotals(shiftId, _vm.total, 0.0, _vm.effectiveDiscount);
      await _vm.loadData();

      if (!mounted) return;

      // Save invoice ID for print and display
      _vm.setLastInvoiceId(invoiceId);

      // Reset cart for next invoice
      _vm.resetForNewInvoice();
      _searchController.clear();
      _isSearching = false;

      // Show completion overlay
      _vm.setCheckoutPhase(CheckoutPhase.completed);
    } catch (e) {
      if (mounted) {
        _vm.setCheckoutPhase(CheckoutPhase.idle);
        context.showErrorSnackBar('حدث خطأ أثناء حفظ الفاتورة');
      }
    }
  }

  /// Cancel checkout – go back to idle
  void _cancelCheckout() {
    _vm.setCheckoutPhase(CheckoutPhase.idle);
  }

  /// Dismiss completion overlay – go back to idle
  void _dismissCompletion() {
    _vm.setCheckoutPhase(CheckoutPhase.idle);
    _vm.setLastInvoiceId('');
  }

  // ── Checkout Confirmation Overlay (delegates to extracted widget) ──
  Widget _buildCheckoutConfirmationOverlay() {
    return PosCheckoutConfirmationOverlay(
      vm: _vm,
      onConfirm: _confirmCheckout,
      onCancel: _cancelCheckout,
    );
  }

  // ── Checkout Completed Overlay (delegates to extracted widget) ────
  Widget _buildCheckoutCompletedOverlay() {
    return PosCheckoutCompletedOverlay(
      vm: _vm,
      onDismiss: _dismissCompletion,
      onPrint: () => _showPrintOptions(_vm.lastInvoiceId),
    );
  }

  /// Show print options (delegates to extracted dialog)
  void _showPrintOptions(String invoiceId) {
    showPrintOptionsDialog(
      context,
      invoiceId,
      onPdfPrint: _printPdfInvoice,
      onBluetoothPrint: _printBluetoothReceipt,
    );
  }

  /// Print invoice as PDF.
  Future<void> _printPdfInvoice(String invoiceId) async {
    try {
      final invoiceData =
          await locator<InvoiceRepository>().getInvoiceById(invoiceId);
      if (invoiceData == null) {
        if (mounted) context.showErrorSnackBar('لم يتم العثور على الفاتورة');
        return;
      }
      final itemsData =
          await locator<InvoiceRepository>().getInvoiceItems(invoiceId);
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
      final currencySymbol = _vm.selectedCurrency == 'SAR'
          ? 'ر.س'
          : _vm.selectedCurrency == 'USD'
              ? r'$'
              : 'ر.ي';

      await printerService.printReceipt({
        'invoice_number': invoiceId,
        'invoice_type': 'فاتورة نقاط بيع',
        'date': DateTime.now(),
        'customer_name': _vm.selectedCustomerName.isEmpty
            ? 'بدون عميل'
            : _vm.selectedCustomerName,
        'items': _vm.cartItems
            .map((item) => <String, dynamic>{
                  'product_name': item.name,
                  'unit_name': item.unitName,
                  'quantity': item.quantity,
                  'unit_price': item.unitPrice,
                  'total_price': item.total,
                })
            .toList(),
        'subtotal': _vm.subtotal,
        'discount': _vm.effectiveDiscount,
        'tax': _vm.tax,
        'total': _vm.total,
        'paid': _vm.total,
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
    if (_vm.activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    await _vm.holdOrder();
    if (!mounted) return;
    _searchController.clear();
    _isSearching = false;
    _sheetController.animateTo(0.12,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    context.showSuccessSnackBar('تم تعليق الطلب');
  }

  /// Show held orders (delegates to extracted dialog)
  void _showHeldOrders() {
    showHeldOrdersDialog(context, _vm, () {
      _sheetController.animateTo(0.5,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BARCODE SCANNER
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _scanBarcode() async {
    if (_vm.activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      final matchResult = await _vm.tryBarcodeMatch(result);
      if (matchResult != null) {
        _addToCartWithUnit(matchResult.product, unitInfo: matchResult.unitInfo);
      } else {
        if (mounted) {
          context
              .showErrorSnackBar('لم يتم العثور على منتج بالباركود: $result');
        }
      }
    }
  }
}
