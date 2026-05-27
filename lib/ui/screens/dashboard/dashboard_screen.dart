import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../navigation/app_router.dart';
import '../../widgets/animated_entry.dart';

/// The main dashboard screen – the first thing the user sees.
///
/// Modern professional design inspired by best-flutter-ui-templates:
/// 1. Clean Header – greeting + date + action icons
/// 2. Hero Sales Card – large prominent card with daily sales & trend
/// 3. Unified Action Grid – 3×3 paged grid for ALL shortcuts
/// 4. Secondary Metrics – 3 horizontal metric pills
/// 5. Recent Transactions – professional card-based list
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  double _todaySales = 0.0;
  int _todayInvoiceCount = 0;
  double _monthSales = 0.0;
  double _monthPurchases = 0.0;
  int _customerCount = 0;
  double _yesterdaySales = 0.0;
  List<Map<String, dynamic>> _recentInvoices = [];
  bool _isLoading = true;

  // Faster periodic refresh timer (15s)
  Timer? _refreshTimer;

  // Animation controllers
  late AnimationController _entryController;
  late AnimationController _chartDrawController;

  // Page controller for the 3×3 action grid
  final _actionPageController = PageController();
  int _currentActionPage = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    WidgetsBinding.instance.addObserver(this);

    // Auto-refresh every 15 seconds for near-real-time updates
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadDashboardData(),
    );

    // Entry animation
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    // Chart line draw animation
    _chartDrawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _entryController.dispose();
    _chartDrawController.dispose();
    _actionPageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDashboardData();
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final db = DatabaseHelper();
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));

      final results = await Future.wait([
        db.getTotalSalesForDate(now),
        db.getInvoiceCountForDate(now),
        db.getTotalSalesThisMonth(),
        db.getTotalPurchasesThisMonth(),
        db.getCustomerCount(),
        db.getRecentInvoices(limit: 5),
        db.getTotalSalesForDate(yesterday),
      ]);

      if (mounted) {
        setState(() {
          _todaySales = (results[0] as num?)?.toDouble() ?? 0.0;
          _todayInvoiceCount = (results[1] as num?)?.toInt() ?? 0;
          _monthSales = (results[2] as num?)?.toDouble() ?? 0.0;
          _monthPurchases = (results[3] as num?)?.toDouble() ?? 0.0;
          _customerCount = (results[4] as num?)?.toInt() ?? 0;
          _recentInvoices =
              (results[5] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
                  [];
          _yesterdaySales = (results[6] as num?)?.toDouble() ?? 0.0;
          _isLoading = false;
        });

        if (!_chartDrawController.isCompleted) {
          _chartDrawController.forward();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في تحميل البيانات: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Navigate to a route and refresh dashboard data when returning.
  void _navigateTo(String route) {
    AppRouter.push(context, route).then((_) => _loadDashboardData());
  }

  // ══════════════════════════════════════════════════════════════════
  //  ALL ACTION ITEMS — unified single list
  // ══════════════════════════════════════════════════════════════════
  List<_ActionItem> get _allActions => [
        // Row 1: Quick Ops
        _ActionItem(label: 'نقطة البيع', icon: Icons.point_of_sale_rounded, color: const Color(0xFF4F6AF0), bgColor: const Color(0xFFEEF0FF), route: AppConstants.pos),
        _ActionItem(label: 'فاتورة بيع', icon: Icons.receipt_long_rounded, color: const Color(0xFF22C55E), bgColor: const Color(0xFFECFDF5), route: AppConstants.newSaleInvoice),
        _ActionItem(label: 'فاتورة شراء', icon: Icons.shopping_cart_rounded, color: const Color(0xFFF97316), bgColor: const Color(0xFFFFF7ED), route: AppConstants.newPurchaseInvoice),
        // Row 2: Quick Ops continued
        _ActionItem(label: 'المصروفات', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFFEF4444), bgColor: const Color(0xFFFEF2F2), route: AppConstants.expenses),
        _ActionItem(label: 'العملاء', icon: Icons.people_rounded, color: const Color(0xFF22C55E), bgColor: const Color(0xFFECFDF5), route: AppConstants.customers),
        _ActionItem(label: 'الموردون', icon: Icons.local_shipping_rounded, color: const Color(0xFF3B82F6), bgColor: const Color(0xFFEFF6FF), route: AppConstants.suppliers),
        // Row 3
        _ActionItem(label: 'المنتجات', icon: Icons.inventory_2_rounded, color: const Color(0xFFF97316), bgColor: const Color(0xFFFFF7ED), route: AppConstants.products),
        _ActionItem(label: 'الفواتير', icon: Icons.receipt_rounded, color: const Color(0xFF4F6AF0), bgColor: const Color(0xFFEEF0FF), route: AppConstants.invoices),
        _ActionItem(label: 'المستودعات', icon: Icons.warehouse_rounded, color: const Color(0xFF8B5CF6), bgColor: const Color(0xFFF5F3FF), route: AppConstants.warehouses),
        // Page 2 — Row 1
        _ActionItem(label: 'الصناديق', icon: Icons.credit_card_rounded, color: const Color(0xFF06B6D4), bgColor: const Color(0xFFECFEFF), route: AppConstants.cashBoxes),
        _ActionItem(label: 'الموظفين', icon: Icons.badge_rounded, color: const Color(0xFFEC4899), bgColor: const Color(0xFFFDF2F8), route: AppConstants.employees),
        _ActionItem(label: 'العملات', icon: Icons.currency_exchange_rounded, color: const Color(0xFF14B8A6), bgColor: const Color(0xFFF0FDFA), route: AppConstants.currencies),
        // Row 2
        _ActionItem(label: 'التقارير', icon: Icons.bar_chart_rounded, color: const Color(0xFF4F6AF0), bgColor: const Color(0xFFEEF0FF), route: AppConstants.reports),
        _ActionItem(label: 'الإحصائيات', icon: Icons.insights_rounded, color: const Color(0xFF8B5CF6), bgColor: const Color(0xFFF5F3FF), route: AppConstants.statistics),
        _ActionItem(label: 'دليل الحسابات', icon: Icons.account_tree_rounded, color: const Color(0xFF06B6D4), bgColor: const Color(0xFFECFEFF), route: AppConstants.chartOfAccounts),
        // Row 3
        _ActionItem(label: 'الإعدادات', icon: Icons.settings_rounded, color: const Color(0xFF6B7280), bgColor: const Color(0xFFF9FAFB), route: AppConstants.settings),
        _ActionItem(label: 'الدعم الفني', icon: Icons.support_agent_rounded, color: const Color(0xFFF97316), bgColor: const Color(0xFFFFF7ED), route: AppConstants.support),
      ];

  int get _totalPages => (_allActions.length / 9).ceil();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FE),
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Clean Header ─────────────────────────────────────
            SliverToBoxAdapter(child: _buildHeader(context, isDark)),

            // ── Hero Sales Card ──────────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 80),
                child: _buildHeroSalesCard(context, isDark),
              ),
            ),

            // ── Unified Action Grid (3×3 paged) ──────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 150),
                child: _buildActionGrid(context, isDark),
              ),
            ),

            // ── Secondary Metrics (3 horizontal cards) ───────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 220),
                child: _buildSecondaryMetrics(context, isDark),
              ),
            ),

            // ── Recent transactions ──────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 300),
                child: _buildSectionHeader(
                  context,
                  'آخر المعاملات',
                  actionLabel: 'عرض الكل',
                  onAction: () => _navigateTo(AppConstants.invoices),
                ),
              ),
            ),
            _buildRecentTransactions(context, isDark),

            // ── Bottom spacing for nav bar + system bar ──────────
            SliverToBoxAdapter(
              child: SizedBox(height: 120 + bottomPadding),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  CLEAN HEADER
  // ══════════════════════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final greeting = DateFormatter.getGreeting();
    final dateStr =
        '${DateFormatter.dayName(now)}، ${DateFormatter.formatDateLong(now)}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20, MediaQuery.of(context).padding.top + 12, 20, 16,
      ),
      color: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FE),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _entryController, curve: Curves.fastOutSlowIn),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      fontWeight: FontWeight.w800, fontSize: 22,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(dateStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _HeaderActionIcon(icon: Icons.notifications_none_rounded, isDark: isDark, onTap: () => _navigateTo(AppConstants.notifications)),
                const SizedBox(width: 8),
                _HeaderActionIcon(icon: Icons.menu_rounded, isDark: isDark, onTap: () => Scaffold.of(context).openEndDrawer()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  HERO SALES CARD
  // ══════════════════════════════════════════════════════════════════
  Widget _buildHeroSalesCard(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    double trendPercent = 0.0;
    bool isTrendUp = true;
    if (_yesterdaySales > 0) {
      trendPercent = ((_todaySales - _yesterdaySales) / _yesterdaySales * 100);
      isTrendUp = trendPercent >= 0;
      trendPercent = trendPercent.abs();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF262640)]
                : [const Color(0xFF4F6AF0), const Color(0xFF6C8CFF)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F6AF0).withValues(alpha: isDark ? 0.2 : 0.3),
              offset: const Offset(0, 8), blurRadius: 24,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(left: -30, top: -30, child: Container(width: 120, height: 120, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
            Positioned(right: -20, bottom: -40, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.04)))),
            // Mini chart
            Positioned(left: 20, bottom: 16, right: 20,
              child: SizedBox(height: 50, child: CustomPaint(painter: _MiniChartPainter(progress: _chartDrawController, lineColor: Colors.white.withValues(alpha: 0.3), fillColor: Colors.white.withValues(alpha: 0.08)))),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('إجمالي مبيعات اليوم',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('$_todayInvoiceCount', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          Text('فاتورة', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CountUpText(value: _todaySales,
                    style: theme.textTheme.displaySmall!.copyWith(color: Colors.white, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5),
                    isLoading: _isLoading),
                  const SizedBox(height: 12),
                  if (_yesterdaySales > 0 || _todaySales > 0)
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: isTrendUp ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isTrendUp ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: isTrendUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5), size: 14),
                          const SizedBox(width: 4),
                          Text('${trendPercent.toStringAsFixed(1)}%', style: theme.textTheme.labelSmall?.copyWith(color: isTrendUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5), fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text(isTrendUp ? 'أكثر من أمس' : 'أقل من أمس', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  UNIFIED 3×3 PAGED ACTION GRID
  // ══════════════════════════════════════════════════════════════════
  Widget _buildActionGrid(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          // Section header
          _buildSectionHeader(context, 'الخدمات'),
          const SizedBox(height: 14),

          // 3×3 paged grid
          SizedBox(
            height: 310,
            child: PageView.builder(
              controller: _actionPageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (page) => setState(() => _currentActionPage = page),
              itemCount: _totalPages,
              itemBuilder: (context, pageIndex) {
                final startIdx = pageIndex * 9;
                final endIdx = math.min(startIdx + 9, _allActions.length);
                final pageItems = _allActions.sublist(startIdx, endIdx);

                // Pad to 9 items so the grid stays consistent
                while (pageItems.length < 9) {
                  pageItems.add(const _ActionItem(label: '', icon: null, color: Colors.transparent, route: ''));
                }

                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: 9,
                  itemBuilder: (context, index) {
                    final item = pageItems[index];
                    if (item.icon == null) return const SizedBox.shrink();
                    return _GridActionCard(
                      label: item.label,
                      icon: item.icon!,
                      color: item.color,
                      bgColor: item.bgColor,
                      isDark: isDark,
                      onTap: () => _navigateTo(item.route),
                    );
                  },
                );
              },
            ),
          ),

          // Page indicators
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (index) {
                  final isActive = index == _currentActionPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.fastOutSlowIn,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF4F6AF0)
                          : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SECONDARY METRICS (3 horizontal cards)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSecondaryMetrics(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final metrics = [
      _MetricData(label: 'مبيعات الشهر', value: _monthSales, icon: Icons.trending_up_rounded, color: const Color(0xFF22C55E), isCount: false),
      _MetricData(label: 'مشتريات الشهر', value: _monthPurchases, icon: Icons.shopping_bag_rounded, color: const Color(0xFFF97316), isCount: false),
      _MetricData(label: 'العملاء', value: _customerCount.toDouble(), icon: Icons.people_rounded, color: const Color(0xFF4F6AF0), isCount: true),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: metrics.asMap().entries.map((entry) {
          final m = entry.value;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(left: entry.key == 0 ? 0 : 6, right: entry.key == metrics.length - 1 ? 0 : 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, 2), blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: m.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(m.icon, color: m.color, size: 16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    m.isCount ? m.value.toInt().toString() : CurrencyFormatter.formatCompactWithSymbol(m.value),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(m.label,
                    style: theme.textTheme.labelSmall?.copyWith(color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SECTION HEADER — Professional with accent + action link
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSectionHeader(BuildContext context, String title, {String? actionLabel, VoidCallback? onAction}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          // Accent dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4F6AF0), Color(0xFF6C8CFF)]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          // Title
          Expanded(
            child: Text(title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
                letterSpacing: 0.3,
                color: isDark ? AppColors.darkTextPrimary : const Color(0xFF2D3436),
              ),
            ),
          ),
          // Optional action link
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(actionLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: const Color(0xFF4F6AF0),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_back_ios_rounded, size: 12, color: Color(0xFF4F6AF0)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  RECENT TRANSACTIONS — Professional card-based design
  // ══════════════════════════════════════════════════════════════════
  Widget _buildRecentTransactions(BuildContext context, bool isDark) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    if (_recentInvoices.isEmpty) {
      return SliverToBoxAdapter(
        child: AnimatedEntry(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), shape: BoxShape.circle),
                child: Icon(Icons.receipt_long_rounded, size: 32, color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 16),
              Text('لا توجد معاملات بعد',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _recentInvoices.length) {
            final invoice = _recentInvoices[index];
            final entityName = invoice['entity_name'] as String? ?? '—';
            final amount = (invoice['total'] as num?)?.toDouble() ?? 0.0;
            final date = DateTime.tryParse(invoice['created_at'] as String? ?? '') ?? DateTime.now();
            final statusStr = invoice['status'] as String? ?? 'pending';
            final invoiceType = invoice['type'] as String? ?? 'sale';
            final isSale = invoiceType.contains('sale') || invoiceType == 'pos';
            final isPaid = statusStr.toLowerCase() == 'paid';

            return AnimatedEntry(
              delay: Duration(milliseconds: 60 * index),
              offset: 16.0,
              child: _ProfessionalTransactionTile(
                entityName: entityName,
                amount: amount,
                date: date,
                isSale: isSale,
                isPaid: isPaid,
                isDark: isDark,
                onTap: () {},
              ),
            );
          }

          // "عرض الكل" button
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF4F6AF0), Color(0xFF6C8CFF)], begin: Alignment.centerRight, end: Alignment.centerLeft),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF4F6AF0).withValues(alpha: 0.25), offset: const Offset(0, 4), blurRadius: 12),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _navigateTo(AppConstants.invoices),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('عرض الكل', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_back, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        childCount: _recentInvoices.length + 1,
      ),
    );
  }

}

// ══════════════════════════════════════════════════════════════════════
//  INTERNAL HELPER CLASSES
// ══════════════════════════════════════════════════════════════════════

class _ActionItem {
  const _ActionItem({required this.label, required this.icon, required this.color, required this.route, this.bgColor});
  final String label;
  final IconData? icon;
  final Color color;
  final Color? bgColor;
  final String route;
}

class _MetricData {
  const _MetricData({required this.label, required this.value, required this.icon, required this.color, required this.isCount});
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool isCount;
}

// ── Header action icon ─────────────────────────────────────────────
class _HeaderActionIcon extends StatelessWidget {
  const _HeaderActionIcon({required this.icon, required this.isDark, required this.onTap});
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), offset: const Offset(0, 2), blurRadius: 8)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Icon(icon, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

// ── Grid Action Card (3×3 items) ──────────────────────────────────
class _GridActionCard extends StatelessWidget {
  const _GridActionCard({
    required this.label,
    required this.icon,
    required this.color,
    this.bgColor,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color? bgColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBg = bgColor ?? color.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, 2), blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: color.withValues(alpha: 0.1),
          highlightColor: color.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon container with solid background
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: isDark ? color.withValues(alpha: 0.15) : effectiveBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 10),
                // Label
                Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Professional Transaction Tile ──────────────────────────────────
class _ProfessionalTransactionTile extends StatelessWidget {
  const _ProfessionalTransactionTile({
    required this.entityName,
    required this.amount,
    required this.date,
    required this.isSale,
    required this.isPaid,
    required this.isDark,
    required this.onTap,
  });

  final String entityName;
  final double amount;
  final DateTime date;
  final bool isSale;
  final bool isPaid;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Icon and colors based on type
    final icon = isSale ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final iconBgColor = isSale
        ? const Color(0xFF22C55E).withValues(alpha: isDark ? 0.15 : 0.1)
        : const Color(0xFFEF4444).withValues(alpha: isDark ? 0.15 : 0.1);
    final iconColor = isSale ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    // Status
    final statusLabel = isPaid ? 'مدفوعة' : 'غير مدفوعة';
    final statusBgColor = isPaid
        ? const Color(0xFF22C55E).withValues(alpha: 0.1)
        : const Color(0xFFF97316).withValues(alpha: 0.1);
    final statusColor = isPaid ? const Color(0xFF22C55E) : const Color(0xFFF97316);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.03),
                offset: const Offset(0, 2), blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              // Type icon
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Entity name + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entityName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormatter.formatDate(date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Amount + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Count-up text widget ─────────────────────────────────────────
class _CountUpText extends StatefulWidget {
  const _CountUpText({required this.value, required this.style, required this.isLoading});
  final double value;
  final TextStyle style;
  final bool isLoading;

  @override
  State<_CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<_CountUpText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _animation = Tween<double>(begin: 0, end: widget.value).animate(CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn));
    if (!widget.isLoading) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || (!widget.isLoading && oldWidget.isLoading)) {
      _previousValue = oldWidget.value;
      _animation = Tween<double>(begin: _previousValue, end: widget.value).animate(CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Text(CurrencyFormatter.format(_animation.value), style: widget.style),
    );
  }
}

// ── Mini Chart Painter ────────────────────────────────────────────
class _MiniChartPainter extends CustomPainter {
  _MiniChartPainter({required this.progress, required this.lineColor, required this.fillColor}) : super(repaint: progress);
  final Animation<double> progress;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final animatedProgress = progress.value;
    if (animatedProgress <= 0) return;

    final points = [
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.15, size.height * 0.5),
      Offset(size.width * 0.3, size.height * 0.65),
      Offset(size.width * 0.45, size.height * 0.3),
      Offset(size.width * 0.6, size.height * 0.45),
      Offset(size.width * 0.75, size.height * 0.15),
      Offset(size.width * 0.9, size.height * 0.25),
      Offset(size.width, size.height * 0.1),
    ];

    final visibleCount = (points.length * animatedProgress).ceil();
    if (visibleCount < 2) return;
    final visiblePoints = points.sublist(0, visibleCount);

    final fillPath = Path();
    fillPath.moveTo(visiblePoints[0].dx, size.height);
    fillPath.lineTo(visiblePoints[0].dx, visiblePoints[0].dy);
    for (int i = 1; i < visiblePoints.length; i++) {
      final prev = visiblePoints[i - 1]; final curr = visiblePoints[i];
      final cpx = (prev.dx + curr.dx) / 2;
      fillPath.cubicTo(cpx, prev.dy, cpx, curr.dy, curr.dx, curr.dy);
    }
    fillPath.lineTo(visiblePoints.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path();
    linePath.moveTo(visiblePoints[0].dx, visiblePoints[0].dy);
    for (int i = 1; i < visiblePoints.length; i++) {
      final prev = visiblePoints[i - 1]; final curr = visiblePoints[i];
      final cpx = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpx, prev.dy, cpx, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(linePath, Paint()..color = lineColor..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    if (visiblePoints.isNotEmpty) {
      canvas.drawCircle(visiblePoints.last, 3, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) => true;
}
