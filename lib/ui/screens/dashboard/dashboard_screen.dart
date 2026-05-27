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
import '../../widgets/transaction_tile.dart';

/// The main dashboard screen – the first thing the user sees.
///
/// Modern clean design inspired by 2026 fintech dashboards:
/// 1. Clean Header – greeting + date + action icons (no gradient)
/// 2. Hero Sales Card – large prominent card with daily sales & trend
/// 3. Quick Actions Grid – 2×2 cards with modern rounded icons
/// 4. Secondary Metrics – 3 horizontal metric pills
/// 5. Management Grid – compact icon grid for all services
/// 6. Recent Transactions – clean list with dividers
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
  double _cashBalance = 0.0;
  double _yesterdaySales = 0.0;
  List<Map<String, dynamic>> _recentInvoices = [];
  bool _isLoading = true;

  // Faster periodic refresh timer (15s instead of 60s)
  Timer? _refreshTimer;

  // Animation controllers
  late AnimationController _entryController;
  late AnimationController _chartDrawController;

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
        db.getCashBalance(),
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
          _cashBalance = (results[5] as num?)?.toDouble() ?? 0.0;
          _recentInvoices =
              (results[6] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
                  [];
          _yesterdaySales = (results[7] as num?)?.toDouble() ?? 0.0;
          _isLoading = false;
        });

        // Start chart animation after data loads
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
    AppRouter.push(context, route).then((_) {
      // Immediately refresh when returning from any screen
      _loadDashboardData();
    });
  }

  // ══════════════════════════════════════════════════════════════════
  //  QUICK ACTION DATA
  // ══════════════════════════════════════════════════════════════════

  List<_ActionItem> get _quickActions => [
        _ActionItem(
          label: 'نقطة البيع',
          icon: Icons.point_of_sale_rounded,
          color: const Color(0xFF4F6AF0),
          bgColor: const Color(0xFFEEF0FF),
          route: AppConstants.pos,
        ),
        _ActionItem(
          label: 'فاتورة بيع',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF22C55E),
          bgColor: const Color(0xFFECFDF5),
          route: AppConstants.newSaleInvoice,
        ),
        _ActionItem(
          label: 'فاتورة شراء',
          icon: Icons.shopping_cart_rounded,
          color: const Color(0xFFF97316),
          bgColor: const Color(0xFFFFF7ED),
          route: AppConstants.newPurchaseInvoice,
        ),
        _ActionItem(
          label: 'المصروفات',
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEF2F2),
          route: AppConstants.expenses,
        ),
      ];

  List<_ActionItem> get _managementActions => [
        _ActionItem(
            label: 'العملاء',
            icon: Icons.people_rounded,
            color: const Color(0xFF22C55E),
            route: AppConstants.customers),
        _ActionItem(
            label: 'الموردون',
            icon: Icons.local_shipping_rounded,
            color: const Color(0xFF3B82F6),
            route: AppConstants.suppliers),
        _ActionItem(
            label: 'المنتجات',
            icon: Icons.inventory_2_rounded,
            color: const Color(0xFFF97316),
            route: AppConstants.products),
        _ActionItem(
            label: 'الفواتير',
            icon: Icons.receipt_rounded,
            color: const Color(0xFF4F6AF0),
            route: AppConstants.invoices),
        _ActionItem(
            label: 'المستودعات',
            icon: Icons.warehouse_rounded,
            color: const Color(0xFF8B5CF6),
            route: AppConstants.warehouses),
        _ActionItem(
            label: 'الصناديق',
            icon: Icons.credit_card_rounded,
            color: const Color(0xFF06B6D4),
            route: AppConstants.cashBoxes),
        _ActionItem(
            label: 'الموظفين',
            icon: Icons.badge_rounded,
            color: const Color(0xFFEC4899),
            route: AppConstants.employees),
        _ActionItem(
            label: 'العملات',
            icon: Icons.currency_exchange_rounded,
            color: const Color(0xFF14B8A6),
            route: AppConstants.currencies),
      ];

  List<_ActionItem> get _reportActions => [
        _ActionItem(
            label: 'التقارير',
            icon: Icons.bar_chart_rounded,
            color: const Color(0xFF4F6AF0),
            route: AppConstants.reports),
        _ActionItem(
            label: 'الإحصائيات',
            icon: Icons.insights_rounded,
            color: const Color(0xFF8B5CF6),
            route: AppConstants.statistics),
        _ActionItem(
            label: 'دليل الحسابات',
            icon: Icons.account_tree_rounded,
            color: const Color(0xFF06B6D4),
            route: AppConstants.chartOfAccounts),
        _ActionItem(
            label: 'الإعدادات',
            icon: Icons.settings_rounded,
            color: const Color(0xFF6B7280),
            route: AppConstants.settings),
        _ActionItem(
            label: 'الدعم الفني',
            icon: Icons.support_agent_rounded,
            color: const Color(0xFFF97316),
            route: AppConstants.support),
      ];

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

            // ── Quick Actions (2×2) ──────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 150),
                child: _buildQuickActions(context, isDark),
              ),
            ),

            // ── Secondary Metrics (3 horizontal cards) ───────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 220),
                child: _buildSecondaryMetrics(context, isDark),
              ),
            ),

            // ── Management Section ───────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 280),
                child: _buildManagementSection(context, isDark),
              ),
            ),

            // ── Reports & Settings Section ───────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 340),
                child: _buildReportsSection(context, isDark),
              ),
            ),

            // ── Recent transactions ──────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 400),
                child: _buildSectionHeader(context, 'آخر المعاملات'),
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
        20,
        MediaQuery.of(context).padding.top + 12,
        20,
        16,
      ),
      color: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FE),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entryController,
          curve: Curves.fastOutSlowIn,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Greeting section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            // Action icons
            Row(
              children: [
                _HeaderActionIcon(
                  icon: Icons.notifications_none_rounded,
                  isDark: isDark,
                  onTap: () => _navigateTo(AppConstants.notifications),
                ),
                const SizedBox(width: 8),
                _HeaderActionIcon(
                  icon: Icons.menu_rounded,
                  isDark: isDark,
                  onTap: () => Scaffold.of(context).openEndDrawer(),
                ),
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

    // Calculate trend percentage
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F6AF0).withValues(alpha: isDark ? 0.2 : 0.3),
              offset: const Offset(0, 8),
              blurRadius: 24,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            // ── Decorative circles ─────────────────────────────────
            Positioned(
              left: -30,
              top: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: -20,
              bottom: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),

            // ── Mini chart ─────────────────────────────────────────
            Positioned(
              left: 20,
              bottom: 16,
              right: 20,
              child: SizedBox(
                height: 50,
                child: CustomPaint(
                  painter: _MiniChartPainter(
                    progress: _chartDrawController,
                    lineColor: Colors.white.withValues(alpha: 0.3),
                    fillColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),

            // ── Card Content ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: label + invoice count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'إجمالي مبيعات اليوم',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_todayInvoiceCount',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'فاتورة',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Sales amount
                  _CountUpText(
                    value: _todaySales,
                    style: theme.textTheme.displaySmall!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 12),

                  // Trend indicator
                  if (_yesterdaySales > 0 || _todaySales > 0)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isTrendUp
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isTrendUp
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                color: isTrendUp
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFFCA5A5),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${trendPercent.toStringAsFixed(1)}%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isTrendUp
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFFCA5A5),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isTrendUp ? 'أكثر من أمس' : 'أقل من أمس',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  QUICK ACTIONS (2×2)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'العمليات السريعة'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: _quickActions.asMap().entries.map((entry) {
              final item = entry.value;
              return _ModernActionCard(
                label: item.label,
                icon: item.icon,
                color: item.color,
                bgColor: item.bgColor,
                onTap: () => _navigateTo(item.route),
              );
            }).toList(),
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
      _MetricData(
        label: 'مبيعات الشهر',
        value: _monthSales,
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF22C55E),
        isCount: false,
      ),
      _MetricData(
        label: 'مشتريات الشهر',
        value: _monthPurchases,
        icon: Icons.shopping_bag_rounded,
        color: const Color(0xFFF97316),
        isCount: false,
      ),
      _MetricData(
        label: 'العملاء',
        value: _customerCount.toDouble(),
        icon: Icons.people_rounded,
        color: const Color(0xFF4F6AF0),
        isCount: true,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: metrics.asMap().entries.map((entry) {
          final m = entry.value;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(
                left: entry.key == 0 ? 0 : 6,
                right: entry.key == metrics.length - 1 ? 0 : 6,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: m.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(m.icon, color: m.color, size: 16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    m.isCount
                        ? m.value.toInt().toString()
                        : CurrencyFormatter.formatCompactWithSymbol(m.value),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
  //  MANAGEMENT SECTION (4-column grid)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildManagementSection(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'الإدارة'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
            children: _managementActions.map((item) {
              return _CompactActionItem(
                label: item.label,
                icon: item.icon,
                color: item.color,
                isDark: isDark,
                onTap: () => _navigateTo(item.route),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  REPORTS & SETTINGS SECTION (horizontal scrollable)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildReportsSection(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: _buildSectionHeader(context, 'التقارير والإعدادات'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 4, left: 16),
              itemCount: _reportActions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = _reportActions[index];
                return _CompactActionItem(
                  label: item.label,
                  icon: item.icon,
                  color: item.color,
                  isDark: isDark,
                  onTap: () => _navigateTo(item.route),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SECTION HEADER
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  RECENT TRANSACTIONS
  // ══════════════════════════════════════════════════════════════════
  Widget _buildRecentTransactions(BuildContext context, bool isDark) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    if (_recentInvoices.isEmpty) {
      return SliverToBoxAdapter(
        child: AnimatedEntry(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 32,
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    size: 32,
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'لا توجد معاملات بعد',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _recentInvoices.length) {
            final invoice = _recentInvoices[index];
            final statusStr = invoice['status'] as String? ?? 'pending';
            final transactionStatus = _mapInvoiceStatus(statusStr);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedEntry(
                  delay: Duration(milliseconds: 60 * index),
                  offset: 16.0,
                  child: TransactionTile(
                    customerName:
                        invoice['entity_name'] as String? ?? '—',
                    amount:
                        (invoice['total'] as num?)?.toDouble() ?? 0.0,
                    date: DateTime.tryParse(
                            invoice['created_at'] as String? ?? '') ??
                        DateTime.now(),
                    status: transactionStatus,
                    onTap: () {
                      // TODO: Navigate to invoice detail
                    },
                  ),
                ),
                if (index < _recentInvoices.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDark
                          ? AppColors.darkDivider.withValues(alpha: 0.3)
                          : AppColors.divider.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            );
          }

          // "عرض الكل" button
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F6AF0), Color(0xFF6C8CFF)],
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F6AF0).withValues(alpha: 0.25),
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    ),
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
                          Text(
                            'عرض الكل',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 16,
                          ),
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

  TransactionStatus _mapInvoiceStatus(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return TransactionStatus.paid;
      case 'unpaid':
        return TransactionStatus.unpaid;
      case 'partial':
        return TransactionStatus.pending;
      default:
        return TransactionStatus.pending;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
//  INTERNAL HELPER CLASSES
// ══════════════════════════════════════════════════════════════════════

class _ActionItem {
  const _ActionItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    this.bgColor,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color? bgColor;
  final String route;
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isCount,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool isCount;
}

// ── Header action icon ─────────────────────────────────────────────
class _HeaderActionIcon extends StatelessWidget {
  const _HeaderActionIcon({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Icon(
            icon,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ── Modern Action Card (2×2 quick ops) ────────────────────────────
class _ModernActionCard extends StatelessWidget {
  const _ModernActionCard({
    required this.label,
    required this.icon,
    required this.color,
    this.bgColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color? bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveBgColor = bgColor ?? color.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, 2),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with solid colored background
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isDark
                        ? color.withValues(alpha: 0.15)
                        : effectiveBgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(height: 12),
                // Label
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
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

// ── Compact Action Item (management grid) ─────────────────────────
class _CompactActionItem extends StatelessWidget {
  const _CompactActionItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.03),
              offset: const Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Count-up text widget ─────────────────────────────────────────
class _CountUpText extends StatefulWidget {
  const _CountUpText({
    required this.value,
    required this.style,
    required this.isLoading,
  });

  final double value;
  final TextStyle style;
  final bool isLoading;

  @override
  State<_CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<_CountUpText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _animation = Tween<double>(begin: 0, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn),
    );

    if (!widget.isLoading) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always re-animate when value changes (not just loading → loaded)
    if (oldWidget.value != widget.value || (!widget.isLoading && oldWidget.isLoading)) {
      _previousValue = oldWidget.value;
      _animation = Tween<double>(
        begin: _previousValue,
        end: widget.value,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          CurrencyFormatter.format(_animation.value),
          style: widget.style,
        );
      },
    );
  }
}

// ── Mini Chart Painter (decorative line chart in hero card) ───────
class _MiniChartPainter extends CustomPainter {
  _MiniChartPainter({
    required this.progress,
    required this.lineColor,
    required this.fillColor,
  }) : super(repaint: progress);

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

    // Draw only up to animated progress
    final visibleCount = (points.length * animatedProgress).ceil();
    if (visibleCount < 2) return;

    final visiblePoints = points.sublist(0, visibleCount);

    // Fill path
    final fillPath = Path();
    fillPath.moveTo(visiblePoints[0].dx, size.height);
    fillPath.lineTo(visiblePoints[0].dx, visiblePoints[0].dy);
    for (int i = 1; i < visiblePoints.length; i++) {
      final prev = visiblePoints[i - 1];
      final curr = visiblePoints[i];
      final cpx = (prev.dx + curr.dx) / 2;
      fillPath.cubicTo(cpx, prev.dy, cpx, curr.dy, curr.dx, curr.dy);
    }
    fillPath.lineTo(visiblePoints.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()..color = fillColor;
    canvas.drawPath(fillPath, fillPaint);

    // Line path
    final linePath = Path();
    linePath.moveTo(visiblePoints[0].dx, visiblePoints[0].dy);
    for (int i = 1; i < visiblePoints.length; i++) {
      final prev = visiblePoints[i - 1];
      final curr = visiblePoints[i];
      final cpx = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpx, prev.dy, cpx, curr.dy, curr.dx, curr.dy);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(linePath, linePaint);

    // Dot at the end
    if (visiblePoints.isNotEmpty) {
      final lastPoint = visiblePoints.last;
      canvas.drawCircle(
        lastPoint,
        3,
        Paint()..color = lineColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) => true;
}
