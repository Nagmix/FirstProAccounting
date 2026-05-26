import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/barcode_scanner_screen.dart';
import '../../widgets/cart_item_tile.dart';

/// Point of Sale (POS) screen – shift-gated, optimized for speed with
/// large touch targets.
///
/// Layout: product grid (left 60%) + cart summary (right 40%).
/// All text is Arabic and the layout is fully RTL.
///
/// No operations are allowed without an active shift.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with TickerProviderStateMixin {
  // ── Search ───────────────────────────────────────────────────────
  final _searchController = TextEditingController();

  // ── Cart state ───────────────────────────────────────────────────
  final List<_CartItem> _cart = [];
  String _paymentMethod = 'cash'; // cash, credit, card, ewallet, bank_transfer
  int? _selectedCategoryId;
  double _orderDiscount = 0;
  int? _selectedCustomerId;
  String _selectedCustomerName = '';

  // ── Held orders ──────────────────────────────────────────────────
  final List<_HeldOrder> _heldOrders = [];

  // ── Data from DB ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _categories = [];
  List<Product> _products = [];
  bool _isLoading = true;
  Map<String, dynamic>? _activeShift;
  String _shiftCashBoxName = '';

  // ── Timer for shift duration ─────────────────────────────────────
  late Ticker _ticker;
  Duration _shiftDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadData();
  }

  void _onTick(Duration elapsed) {
    if (_activeShift != null && _activeShift!['opened_at'] != null) {
      final opened = DateTime.parse(_activeShift!['opened_at'].toString());
      setState(() => _shiftDuration = DateTime.now().difference(opened));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    setState(() {
      _categories = catMaps;
      _products = prodMaps.map((m) => Product.fromMap(m)).toList();
      _isLoading = false;
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
        });
        if (!_ticker.isActive) _ticker.start();
        return;
      }
    }
    // No active shift found
    setState(() {
      _activeShift = null;
      _shiftCashBoxName = '';
      _shiftDuration = Duration.zero;
    });
    if (_ticker.isActive) _ticker.stop();
  }

  // ── Computed properties ──────────────────────────────────────────
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
  double get _tax => (_subtotal - _orderDiscount) * (AppConstants.defaultVatRate / 100);
  double get _total => _subtotal - _orderDiscount + _tax;

  String _formatDuration(Duration d) {
    final hours = d.inHours.remainder(24).toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes';
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
                  Column(
                    children: [
                      // ── Shift info bar ──────────────────────────
                      if (_activeShift != null) _buildShiftInfoBar(),
                      // ── Main content ────────────────────────────
                      Expanded(
                        child: context.isMobile
                            ? _buildMobileLayout()
                            : _buildTabletLayout(),
                      ),
                    ],
                  ),
                  // ── Shift overlay when no active shift ──────────
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

  // ── AppBar ───────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('نقطة البيع'),
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
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.warningCircle,
                    size: 44,
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
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _showOpenShiftDialog,
                    icon: const Icon(PhosphorIconsFill.lockOpen, size: 22),
                    label: const Text(
                      'فتح وردية جديدة',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: AppColors.success.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // ── Green dot + "وردية مفتوحة" ────────────────────
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.4),
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
              const SizedBox(width: 16),

              // ── Shift number ───────────────────────────────────
              _shiftInfoChip(
                icon: PhosphorIconsRegular.hash,
                label: 'رقم الوردية',
                value: shift['shift_number']?.toString() ?? '-',
              ),
              const SizedBox(width: 12),

              // ── Cash box name ──────────────────────────────────
              _shiftInfoChip(
                icon: PhosphorIconsRegular.wallet,
                label: 'الصندوق',
                value: _shiftCashBoxName,
              ),
              const SizedBox(width: 12),

              // ── Duration ───────────────────────────────────────
              _shiftInfoChip(
                icon: PhosphorIconsRegular.clock,
                label: 'المدة',
                value: _formatDuration(_shiftDuration),
              ),
              const SizedBox(width: 12),

              // ── Total sales ────────────────────────────────────
              _shiftInfoChip(
                icon: PhosphorIconsRegular.chartLineUp,
                label: 'إجمالي المبيعات',
                value: CurrencyFormatter.format(totalSales),
              ),
              const SizedBox(width: 12),

              // ── Opening amount ─────────────────────────────────
              _shiftInfoChip(
                icon: PhosphorIconsRegular.vault,
                label: 'رصيد الافتتاح',
                value: CurrencyFormatter.format(openingAmount),
              ),
              const SizedBox(width: 16),

              // ── Cash In button ─────────────────────────────────
              _shiftActionButton(
                label: 'إيداع',
                icon: PhosphorIconsRegular.arrowDown,
                color: AppColors.success,
                onTap: () => _showCashInOutDialog(true),
              ),
              const SizedBox(width: 8),

              // ── Cash Out button ────────────────────────────────
              _shiftActionButton(
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

  Widget _shiftInfoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: context.textTheme.bodySmall?.copyWith(
            color: context.textSecondary,
          ),
        ),
        Text(
          value,
          style: context.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _shiftActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
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
  //  TABLET / DESKTOP LAYOUT (60/40 split)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTabletLayout() {
    return Row(
      children: [
        // ── Product grid side (60%) ─────────────────────────────
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _buildSearchBar(),
              _buildCategoryChips(),
              Expanded(child: _buildProductGrid()),
            ],
          ),
        ),

        // ── Vertical divider ────────────────────────────────────
        const VerticalDivider(width: 1),

        // ── Cart side (40%) ─────────────────────────────────────
        Expanded(
          flex: 4,
          child: _buildCartPanel(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MOBILE LAYOUT (stacked)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildCategoryChips(),
        Expanded(
          child: _cart.isEmpty
              ? _buildProductGrid()
              : _buildCartPanel(),
        ),
      ],
    );
  }

  // ── Search bar ───────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'بحث عن منتج أو باركود...',
                prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
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

  // ── Category chips ───────────────────────────────────────────────
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _categories.length + 1, // +1 for "الكل"
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _selectedCategoryId == null;
            return FilterChip(
              avatar: const Icon(PhosphorIconsRegular.squaresFour, size: 16),
              label: const Text('الكل'),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedCategoryId = null);
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
            );
          }
          final cat = _categories[index - 1];
          final isSelected = _selectedCategoryId == cat['id'];
          return FilterChip(
            label: Text(cat['name'] as String),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedCategoryId = cat['id'] as int?);
            },
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            checkmarkColor: AppColors.primary,
          );
        },
      ),
    );
  }

  // ── Product grid ─────────────────────────────────────────────────
  Widget _buildProductGrid() {
    final products = _filteredProducts;

    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsRegular.magnifyingGlass, size: 64, color: AppColors.textHint),
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
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.78,
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

  // ── Cart panel ───────────────────────────────────────────────────
  Widget _buildCartPanel() {
    final isDark = context.isDarkMode;

    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.surfaceVariant,
      child: Column(
        children: [
          // ── Cart header ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'سلة المشتريات',
                      style: context.textTheme.titleSmall,
                    ),
                    if (_selectedCustomerName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(PhosphorIconsRegular.user, size: 14, color: AppColors.info),
                            const SizedBox(width: 4),
                            Text(
                              _selectedCustomerName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _cart.clear();
                      _orderDiscount = 0;
                    }),
                    child: const Text('مسح الكل'),
                  ),
              ],
            ),
          ),

          // ── Cart items ────────────────────────────────────────
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsRegular.shoppingCart,
                            size: 56, color: AppColors.textHint),
                        const SizedBox(height: 8),
                        Text('السلة فارغة',
                            style: context.textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Text('اضغط على المنتج لإضافته',
                            style: context.textTheme.bodySmall),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return CartItemTile(
                        name: item.name,
                        quantity: item.quantity,
                        unitPrice: item.unitPrice,
                        total: item.total,
                        onIncrement: () {
                          setState(() {
                            _cart[index] = item.copyWith(
                              quantity: item.quantity + 1,
                            );
                          });
                        },
                        onDecrement: () {
                          setState(() {
                            if (item.quantity > 1) {
                              _cart[index] = item.copyWith(
                                quantity: item.quantity - 1,
                              );
                            } else {
                              _cart.removeAt(index);
                            }
                          });
                        },
                        onDelete: () {
                          setState(() => _cart.removeAt(index));
                        },
                      );
                    },
                  ),
          ),

          // ── Payment method buttons ────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: Column(
              children: [
                // Customer selector for credit sales
                if (_paymentMethod == 'credit')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: _showCustomerSelector,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.info.withValues(alpha: 0.06),
                        ),
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsRegular.user, size: 18, color: AppColors.info),
                            const SizedBox(width: 8),
                            Text(
                              _selectedCustomerName.isEmpty
                                  ? 'اختر العميل'
                                  : _selectedCustomerName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _selectedCustomerName.isEmpty
                                    ? AppColors.textHint
                                    : AppColors.info,
                              ),
                            ),
                            const Spacer(),
                            const Icon(PhosphorIconsRegular.caretDown, size: 16, color: AppColors.info),
                          ],
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    _paymentButton('نقدي', 'cash', PhosphorIconsRegular.money),
                    const SizedBox(width: 4),
                    _paymentButton('آجل', 'credit', PhosphorIconsRegular.clock),
                    const SizedBox(width: 4),
                    _paymentButton('بطاقة', 'card', PhosphorIconsRegular.creditCard),
                    const SizedBox(width: 4),
                    _paymentButton('محفظة', 'ewallet', PhosphorIconsRegular.wallet),
                    const SizedBox(width: 4),
                    _paymentButton('تحويل', 'bank_transfer', PhosphorIconsRegular.buildings),
                  ],
                ),
              ],
            ),
          ),

          // ── Totals & action buttons ───────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Subtotal
                  _totalRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal)),
                  if (_orderDiscount > 0) ...[
                    const SizedBox(height: 4),
                    _totalRow(
                      'الخصم',
                      '- ${CurrencyFormatter.format(_orderDiscount)}',
                      valueColor: AppColors.error,
                    ),
                  ],
                  if (_tax > 0) ...[
                    const SizedBox(height: 4),
                    _totalRow(
                      'الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)',
                      CurrencyFormatter.format(_tax),
                    ),
                  ],
                  const Divider(height: 16),
                  _totalRow(
                    'الإجمالي',
                    CurrencyFormatter.format(_total),
                    valueStyle: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),

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
                      child: Text(
                        'إنهاء البيع  ${CurrencyFormatter.format(_total)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Hold order button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _cart.isEmpty ? null : _holdOrder,
                      icon: const Icon(PhosphorIconsRegular.pauseCircle, size: 20),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentButton(String label, String method, IconData icon) {
    final selected = _paymentMethod == method;
    return Expanded(
      child: SizedBox(
        height: 38,
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _paymentMethod = method;
              if (method != 'credit') {
                _selectedCustomerId = null;
                _selectedCustomerName = '';
              }
            });
          },
          style: OutlinedButton.styleFrom(
            backgroundColor:
                selected ? AppColors.primary.withValues(alpha: 0.1) : null,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: selected ? AppColors.primary : null),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
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

  Widget _totalRow(
    String label,
    String value, {
    Color? valueColor,
    TextStyle? valueStyle,
  }) {
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
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 20,
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(PhosphorIconsFill.lockOpen, color: AppColors.success, size: 22),
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

              // ── Cash box selector ──────────────────────────────
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
                      final typeLabel = type == 'bank' ? 'بنك' : 'صندوق';
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text('$name ($typeLabel)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) selectedCashBoxId = val;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Opening amount ─────────────────────────────────
              Text('مبلغ الافتتاح', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'أدخل مبلغ الافتتاح',
                  suffixText: AppConstants.currency,
                  prefixIcon: const Icon(PhosphorIconsRegular.vault, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              // ── Notes ──────────────────────────────────────────
              Text('ملاحظات (اختياري)', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'ملاحظات...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),

              // ── Open shift button ──────────────────────────────
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
                    // Check if this cash box already has an active shift
                    final existingShift = await db.getActiveShift(selectedCashBoxId!);
                    if (existingShift != null) {
                      if (mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('يوجد وردية مفتوحة لهذا الصندوق بالفعل'), backgroundColor: AppColors.warning),
                        );
                      }
                      return;
                    }
                    final shiftNumber = await db.getNextShiftNumber();
                    final openingAmount = double.tryParse(amountController.text) ?? 0.0;
                    final now = DateTime.now();
                    final shiftMap = {
                      'shift_number': shiftNumber,
                      'cashier_id': null,
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

                    // Update cash box balance with opening amount
                    if (openingAmount > 0) {
                      final cb = await db.getCashBoxById(selectedCashBoxId!);
                      if (cb != null) {
                        final currentBalance = (cb['balance'] as num?)?.toDouble() ?? 0.0;
                        await db.updateCashBox(selectedCashBoxId!, {
                          'balance': currentBalance + openingAmount,
                          'updated_at': now.toIso8601String(),
                        });
                      }
                    }

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    await _loadActiveShift();
                    context.showSuccessSnackBar('تم فتح الوردية $shiftNumber بنجاح');
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
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 20,
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isCashIn ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCashIn ? PhosphorIconsRegular.arrowDown : PhosphorIconsRegular.arrowUp,
                      color: isCashIn ? AppColors.success : AppColors.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isCashIn ? 'إيداع نقدي' : 'سحب نقدي',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Amount ─────────────────────────────────────────
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

              // ── Reason ─────────────────────────────────────────
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

              // ── Submit button ──────────────────────────────────
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
                    final reason = reasonController.text.trim().isEmpty
                        ? (isCashIn ? 'إيداع نقدي' : 'سحب نقدي')
                        : reasonController.text.trim();

                    final db = DatabaseHelper();
                    final cashBoxId = _activeShift!['cash_box_id'] as int;
                    final now = DateTime.now();
                    final journalId = now.millisecondsSinceEpoch;

                    // Update cash box balance
                    final cb = await db.getCashBoxById(cashBoxId);
                    if (cb != null) {
                      final currentBalance = (cb['balance'] as num?)?.toDouble() ?? 0.0;
                      await db.updateCashBox(cashBoxId, {
                        'balance': isCashIn ? currentBalance + amount : currentBalance - amount,
                        'updated_at': now.toIso8601String(),
                      });
                    }

                    // Create journal entry
                    // Find cash/banks account and cash_in_out account
                    final dbInstance = await db.database;
                    final cashBanksAccount = await dbInstance.query(
                      'accounts',
                      where: 'account_code = ? AND currency = ?',
                      whereArgs: ['1100', 'YER'],
                      limit: 1,
                    );
                    final cashInOutAccount = await dbInstance.query(
                      'accounts',
                      where: 'account_code LIKE ? AND currency = ?',
                      whereArgs: ['5300%', 'YER'],
                      limit: 1,
                    );

                    final cashBanksId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
                    final cashInOutId = cashInOutAccount.isNotEmpty ? cashInOutAccount.first['id'] as int : null;

                    if (isCashIn) {
                      // Cash In: Debit Cash/Bank, Credit Cash In/Out
                      if (cashBanksId != null) {
                        await dbInstance.insert('transactions', {
                          'account_id': cashBanksId,
                          'journal_id': journalId,
                          'debit': amount,
                          'credit': 0.0,
                          'description': '$reason - وردية ${_activeShift!['shift_number']}',
                          'date': now.toIso8601String(),
                          'created_at': now.toIso8601String(),
                        });
                        await dbInstance.rawUpdate(
                          'UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?',
                          [amount, now.toIso8601String(), cashBanksId],
                        );
                      }
                      if (cashInOutId != null) {
                        await dbInstance.insert('transactions', {
                          'account_id': cashInOutId,
                          'journal_id': journalId,
                          'debit': 0.0,
                          'credit': amount,
                          'description': '$reason - وردية ${_activeShift!['shift_number']}',
                          'date': now.toIso8601String(),
                          'created_at': now.toIso8601String(),
                        });
                        await dbInstance.rawUpdate(
                          'UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?',
                          [amount, now.toIso8601String(), cashInOutId],
                        );
                      }
                    } else {
                      // Cash Out: Debit Cash In/Out, Credit Cash/Bank
                      if (cashInOutId != null) {
                        await dbInstance.insert('transactions', {
                          'account_id': cashInOutId,
                          'journal_id': journalId,
                          'debit': amount,
                          'credit': 0.0,
                          'description': '$reason - وردية ${_activeShift!['shift_number']}',
                          'date': now.toIso8601String(),
                          'created_at': now.toIso8601String(),
                        });
                        await dbInstance.rawUpdate(
                          'UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?',
                          [amount, now.toIso8601String(), cashInOutId],
                        );
                      }
                      if (cashBanksId != null) {
                        await dbInstance.insert('transactions', {
                          'account_id': cashBanksId,
                          'journal_id': journalId,
                          'debit': 0.0,
                          'credit': amount,
                          'description': '$reason - وردية ${_activeShift!['shift_number']}',
                          'date': now.toIso8601String(),
                          'created_at': now.toIso8601String(),
                        });
                        await dbInstance.rawUpdate(
                          'UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?',
                          [amount, now.toIso8601String(), cashBanksId],
                        );
                      }
                    }

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    context.showSuccessSnackBar(
                      isCashIn ? 'تم الإيداع بنجاح: ${CurrencyFormatter.format(amount)}' : 'تم السحب بنجاح: ${CurrencyFormatter.format(amount)}',
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
    final expectedAmount = (shift['expected_amount'] as num?)?.toDouble() ?? openingAmount + totalSales - totalReturns - totalDiscounts;

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
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 20,
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(PhosphorIconsRegular.chartBar, color: AppColors.info, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'تقرير X – منتصف الوردية',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Shift info ─────────────────────────────────────
              _reportRow('رقم الوردية', shift['shift_number']?.toString() ?? '-'),
              _reportRow('الصندوق', _shiftCashBoxName),
              _reportRow('وقت الافتتاح', shift['opened_at'] != null ? DateFormatter.formatDateTime(DateTime.parse(shift['opened_at'].toString())) : '-'),
              _reportRow('المدة', _formatDuration(_shiftDuration)),
              const Divider(height: 24),

              // ── Financial summary ──────────────────────────────
              _reportRow('رصيد الافتتاح', CurrencyFormatter.format(openingAmount), valueColor: AppColors.primary),
              _reportRow('إجمالي المبيعات', CurrencyFormatter.format(totalSales), valueColor: AppColors.success),
              _reportRow('إجمالي المرتجعات', CurrencyFormatter.format(totalReturns), valueColor: AppColors.error),
              _reportRow('إجمالي الخصومات', CurrencyFormatter.format(totalDiscounts), valueColor: AppColors.warning),
              const Divider(height: 24),

              // ── Expected cash ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _reportRow('المتوقع في الصندوق', CurrencyFormatter.format(expectedAmount), valueColor: AppColors.primary, isBold: true),
                    const SizedBox(height: 6),
                    _reportRow('عدد المعاملات', transactionCount.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Close button ───────────────────────────────────
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
  //  Z-REPORT / CLOSE SHIFT
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
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 20,
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(PhosphorIconsRegular.signOut, color: AppColors.error, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'تقرير Z – إغلاق الوردية',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Shift summary ────────────────────────────────
                _reportRow('رقم الوردية', shift['shift_number']?.toString() ?? '-'),
                _reportRow('الصندوق', _shiftCashBoxName),
                _reportRow('وقت الافتتاح', shift['opened_at'] != null ? DateFormatter.formatDateTime(DateTime.parse(shift['opened_at'].toString())) : '-'),
                _reportRow('المدة', _formatDuration(_shiftDuration)),
                const Divider(height: 20),

                _reportRow('رصيد الافتتاح', CurrencyFormatter.format(openingAmount)),
                _reportRow('إجمالي المبيعات', CurrencyFormatter.format(totalSales), valueColor: AppColors.success),
                _reportRow('إجمالي المرتجعات', CurrencyFormatter.format(totalReturns), valueColor: AppColors.error),
                _reportRow('إجمالي الخصومات', CurrencyFormatter.format(totalDiscounts), valueColor: AppColors.warning),
                _reportRow('عدد المعاملات', transactionCount.toString()),
                const Divider(height: 20),

                // ── Expected amount ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: _reportRow('المتوقع في الصندوق', CurrencyFormatter.format(expectedAmount), valueColor: AppColors.primary, isBold: true),
                ),
                const SizedBox(height: 16),

                // ── Actual closing amount input ──────────────────
                Text('المبلغ الفعلي في الصندوق', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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

                // ── Notes ────────────────────────────────────────
                Text('ملاحظات (اختياري)', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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

                // ── Close shift button ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final closingAmount = double.tryParse(closingAmountController.text) ?? expectedAmount;
                      final difference = closingAmount - expectedAmount;
                      final now = DateTime.now();

                      final db = DatabaseHelper();
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

                      // Update cash box balance
                      final cashBoxId = shift['cash_box_id'] as int;
                      final cb = await db.getCashBoxById(cashBoxId);
                      if (cb != null) {
                        await db.updateCashBox(cashBoxId, {
                          'balance': closingAmount,
                          'updated_at': now.toIso8601String(),
                        });
                      }

                      // If difference != 0, create journal entry for Cash Over/Short
                      if ((difference.abs()) > 0.005) {
                        final dbInstance = await db.database;
                        final journalId = now.millisecondsSinceEpoch;

                        // Find cash/banks account
                        final cashBanksAccount = await dbInstance.query(
                          'accounts',
                          where: 'account_code = ? AND currency = ?',
                          whereArgs: ['1100', 'YER'],
                          limit: 1,
                        );

                        // Find or use cash over/short account (5400)
                        final cashOverShortAccount = await dbInstance.query(
                          'accounts',
                          where: 'account_code LIKE ? AND currency = ?',
                          whereArgs: ['5400%', 'YER'],
                          limit: 1,
                        );

                        final cashBanksId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
                        final cashOverShortId = cashOverShortAccount.isNotEmpty ? cashOverShortAccount.first['id'] as int : null;

                        if (difference > 0) {
                          // Overage: Debit Cash, Credit Cash Over/Short
                          if (cashBanksId != null) {
                            await dbInstance.insert('transactions', {
                              'account_id': cashBanksId,
                              'journal_id': journalId,
                              'debit': difference,
                              'credit': 0.0,
                              'description': 'فائض صندوق - وردية ${shift['shift_number']}',
                              'date': now.toIso8601String(),
                              'created_at': now.toIso8601String(),
                            });
                            await dbInstance.rawUpdate(
                              'UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?',
                              [difference, now.toIso8601String(), cashBanksId],
                            );
                          }
                          if (cashOverShortId != null) {
                            await dbInstance.insert('transactions', {
                              'account_id': cashOverShortId,
                              'journal_id': journalId,
                              'debit': 0.0,
                              'credit': difference,
                              'description': 'فائض صندوق - وردية ${shift['shift_number']}',
                              'date': now.toIso8601String(),
                              'created_at': now.toIso8601String(),
                            });
                            await dbInstance.rawUpdate(
                              'UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?',
                              [difference, now.toIso8601String(), cashOverShortId],
                            );
                          }
                        } else {
                          // Shortage: Debit Cash Over/Short, Credit Cash
                          final absDiff = difference.abs();
                          if (cashOverShortId != null) {
                            await dbInstance.insert('transactions', {
                              'account_id': cashOverShortId,
                              'journal_id': journalId,
                              'debit': absDiff,
                              'credit': 0.0,
                              'description': 'عجز صندوق - وردية ${shift['shift_number']}',
                              'date': now.toIso8601String(),
                              'created_at': now.toIso8601String(),
                            });
                            await dbInstance.rawUpdate(
                              'UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?',
                              [absDiff, now.toIso8601String(), cashOverShortId],
                            );
                          }
                          if (cashBanksId != null) {
                            await dbInstance.insert('transactions', {
                              'account_id': cashBanksId,
                              'journal_id': journalId,
                              'debit': 0.0,
                              'credit': absDiff,
                              'description': 'عجز صندوق - وردية ${shift['shift_number']}',
                              'date': now.toIso8601String(),
                              'created_at': now.toIso8601String(),
                            });
                            await dbInstance.rawUpdate(
                              'UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?',
                              [absDiff, now.toIso8601String(), cashBanksId],
                            );
                          }
                        }
                      }

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
                                  (difference.abs()) < 0.005
                                      ? PhosphorIconsFill.checkCircle
                                      : PhosphorIconsRegular.warning,
                                  color: (difference.abs()) < 0.005
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
                                if ((difference.abs()) >= 0.005)
                                  Text(
                                    difference > 0 ? 'فائض: ${CurrencyFormatter.format(difference)}' : 'عجز: ${CurrencyFormatter.format(difference.abs())}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: difference > 0 ? AppColors.success : AppColors.error,
                                    ),
                                  )
                                else
                                  const Text(
                                    'الصندوق متوازن ✓',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
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
                    child: const Text('إغلاق الوردية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
          Text(label, style: context.textTheme.bodyMedium?.copyWith(
            color: context.textSecondary,
          )),
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
    final customers = await db.getAllCustomers(orderBy: 'name ASC');
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
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 20,
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
              Text(
                'اختر العميل',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
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
                height: 300,
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    var filtered = customers;
                    if (searchController.text.isNotEmpty) {
                      final q = searchController.text.toLowerCase();
                      filtered = customers.where((c) =>
                          (c['name']?.toString() ?? '').toLowerCase().contains(q) ||
                          (c['phone']?.toString() ?? '').contains(q)).toList();
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
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════════════
  void _addToCart(Product product) {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    final existingIndex =
        _cart.indexWhere((i) => i.productId == product.id);
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
  }

  Future<void> _checkout() async {
    // Check for active shift
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً قبل إتمام عملية البيع');
      return;
    }

    // Validate credit sale has customer
    if (_paymentMethod == 'credit' && _selectedCustomerId == null) {
      context.showErrorSnackBar('يجب اختيار عميل للبيع آجل');
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
              if (_orderDiscount > 0)
                _reportRow('الخصم', '- ${CurrencyFormatter.format(_orderDiscount)}', valueColor: AppColors.error),
              if (_tax > 0)
                _reportRow('الضريبة', CurrencyFormatter.format(_tax)),
              const Divider(height: 16),
              _reportRow('الإجمالي', CurrencyFormatter.format(_total), valueColor: AppColors.primary, isBold: true),
              const SizedBox(height: 8),
              _reportRow(
                'طريقة الدفع',
                _paymentMethod == 'cash' ? 'نقدي' :
                _paymentMethod == 'credit' ? 'آجل ($_selectedCustomerName)' :
                _paymentMethod == 'card' ? 'بطاقة' :
                _paymentMethod == 'ewallet' ? 'محفظة إلكترونية' :
                'تحويل بنكي',
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

    final invoiceId = const Uuid().v4();
    final isCash = _paymentMethod != 'credit';
    final cashBoxId = _activeShift!['cash_box_id'] as int;

    final invoiceMap = {
      'id': invoiceId,
      'type': 'sale',
      'payment_mechanism': _paymentMethod == 'credit' ? 'credit' : 'cash',
      'payment_method': _paymentMethod == 'card' ? 'bank' : (_paymentMethod == 'ewallet' ? 'ewallet' : (_paymentMethod == 'bank_transfer' ? 'transfer' : _paymentMethod)),
      'is_return': 0,
      'cash_box_id': cashBoxId,
      'customer_id': _selectedCustomerId,
      'supplier_id': null,
      'subtotal': _subtotal,
      'discount_rate': 0.0,
      'discount_amount': _orderDiscount,
      'tax_amount': _tax,
      'total': _total,
      'paid_amount': isCash ? _total : 0.0,
      'remaining': _paymentMethod == 'credit' ? _total : 0.0,
      'status': _paymentMethod == 'credit' ? 'unpaid' : 'paid',
      'cashier_id': null,
      'warehouse_id': null,
      'currency': 'YER',
      'exchange_rate': 1.0,
      'notes': null,
      'created_at': DateTime.now().toIso8601String(),
    };
    final items = _cart.map((item) => {
      'invoice_id': invoiceId,
      'product_id': item.productId,
      'product_name': item.name,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'total_price': item.total,
      'notes': null,
    }).toList();

    final db = DatabaseHelper();
    await db.saveInvoiceWithJournalEntries(
      invoiceMap,
      items,
      invoiceType: 'sale',
      paymentMechanism: _paymentMethod == 'credit' ? 'credit' : 'cash',
      isReturn: false,
      cashBoxId: cashBoxId,
    );

    // Update shift totals
    final shiftId = _activeShift!['id'] as int;
    await db.updateShiftTotals(shiftId, _total, 0.0, _orderDiscount);

    // Update product stock
    for (final item in _cart) {
      final productMap = await db.getProductById(item.productId);
      if (productMap != null) {
        final currentStock = (productMap['current_stock'] as num?)?.toDouble() ?? 0.0;
        await db.updateProduct(item.productId, {
          'current_stock': (currentStock - item.quantity).clamp(0.0, double.infinity),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    }

    // Reload shift data to get updated totals
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
              Text('الإجمالي: ${CurrencyFormatter.format(_total)}'),
              Text('طريقة الدفع: ${_paymentMethod == 'cash' ? 'نقدي' : _paymentMethod == 'credit' ? 'آجل' : _paymentMethod == 'card' ? 'بطاقة' : _paymentMethod == 'ewallet' ? 'محفظة' : 'تحويل'}'),
              if (_selectedCustomerName.isNotEmpty)
                Text('العميل: $_selectedCustomerName'),
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
                  _orderDiscount = 0;
                  _selectedCustomerId = null;
                  _selectedCustomerName = '';
                });
              },
              child: const Text('فاتورة جديدة'),
            ),
          ],
        ),
      ),
    );
  }

  void _holdOrder() {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    _heldOrders.add(_HeldOrder(
      items: List.from(_cart),
      paymentMethod: _paymentMethod,
      discount: _orderDiscount,
      customerId: _selectedCustomerId,
      customerName: _selectedCustomerName,
      createdAt: DateTime.now(),
    ));
    setState(() {
      _cart.clear();
      _orderDiscount = 0;
      _selectedCustomerId = null;
      _selectedCustomerName = '';
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
              Text('الطلبات المعلقة',
                  style: context.textTheme.titleLarge),
              const SizedBox(height: 12),
              ..._heldOrders.asMap().entries.map((entry) {
                final idx = entry.key;
                final order = entry.value;
                final total =
                    order.items.fold(0.0, (s, i) => s + i.total);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.secondary.withValues(alpha: 0.15),
                    child: Text('${idx + 1}'),
                  ),
                  title: Text(
                    '${order.items.length} صنف – ${CurrencyFormatter.format(total.toDouble())}',
                  ),
                  subtitle: Text(
                    '${DateFormatter.formatDateTime(order.createdAt)}${order.customerName.isNotEmpty ? ' – ${order.customerName}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _cart.clear();
                            _cart.addAll(order.items);
                            _paymentMethod = order.paymentMethod;
                            _orderDiscount = order.discount;
                            _selectedCustomerId = order.customerId;
                            _selectedCustomerName = order.customerName;
                            _heldOrders.removeAt(idx);
                          });
                          Navigator.pop(ctx);
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
                        icon: const Icon(PhosphorIconsRegular.trash,
                            color: AppColors.error),
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
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'مبلغ الخصم',
              suffixText: AppConstants.currency,
            ),
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
                  _orderDiscount =
                      double.tryParse(controller.text) ?? 0;
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

  void _scanBarcode() async {
    if (_activeShift == null) {
      context.showErrorSnackBar('يجب فتح وردية أولاً');
      return;
    }
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result != null && result.isNotEmpty) {
      final db = DatabaseHelper();
      final maps = await db.searchProducts(result);
      if (maps.isNotEmpty) {
        final product = Product.fromMap(maps.first);
        _addToCart(product);
      } else {
        if (mounted) {
          context.showErrorSnackBar('لم يتم العثور على منتج بالباركود: $result');
        }
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PRODUCT CARD (grid item)
// ═══════════════════════════════════════════════════════════════════════════
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
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon ───────────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  PhosphorIconsRegular.package,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 8),

              // ── Name ───────────────────────────────────────────
              Text(
                product.nameAr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),

              // ── Price ──────────────────────────────────────────
              Text(
                CurrencyFormatter.format(product.sellPrice),
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),

              // ── Stock badge ────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: outOfStock
                      ? AppColors.errorLight
                      : lowStock
                          ? AppColors.warningLight
                          : AppColors.successLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  outOfStock
                      ? 'نفذ'
                      : lowStock
                          ? 'مخزون منخفض'
                          : '${product.currentStock.toStringAsFixed(0)} قطعة',
                  style: TextStyle(
                    fontSize: 9,
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

// ═══════════════════════════════════════════════════════════════════════════
//  CART ITEM MODEL (local to POS)
// ═══════════════════════════════════════════════════════════════════════════
class _CartItem {
  final int productId;
  final String name;
  final double unitPrice;
  final double quantity;

  _CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  double get total => unitPrice * quantity;

  _CartItem copyWith({int? productId, String? name, double? unitPrice, double? quantity}) {
    return _CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HELD ORDER MODEL
// ═══════════════════════════════════════════════════════════════════════════
class _HeldOrder {
  final List<_CartItem> items;
  final String paymentMethod;
  final double discount;
  final int? customerId;
  final String customerName;
  final DateTime createdAt;

  _HeldOrder({
    required this.items,
    required this.paymentMethod,
    required this.discount,
    this.customerId,
    this.customerName = '',
    required this.createdAt,
  });
}
