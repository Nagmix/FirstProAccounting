import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../navigation/app_router.dart';
import '../../widgets/animated_entry.dart';
import '../../widgets/quick_action_button.dart';
import '../../widgets/transaction_tile.dart';

/// The main dashboard screen – the first thing the user sees.
///
/// Modern design with premium animations and glassmorphism effects:
/// 1. Gradient Header – animated greeting + date + frosted-glass sales summary
/// 2. Pageable service grid with staggered entry animations on page swipe
/// 3. Redesigned statistics cards (2 × 2) with count-up & progress bars
/// 4. Recent transactions list with slide-in & dividers
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  double _todaySales = 0.0;
  int _todayInvoiceCount = 0;
  double _monthSales = 0.0;
  double _monthPurchases = 0.0;
  int _customerCount = 0;
  double _cashBalance = 0.0;
  List<Map<String, dynamic>> _recentInvoices = [];
  bool _isLoading = true;

  // PageView controller for service buttons
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Animation controllers for the header
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _headerEntryController;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    WidgetsBinding.instance.addObserver(this);

    // Pulse animation for chart icon (repeating)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Waving hand animation (repeating)
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Header entry animation
    _headerEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _headerEntryController.dispose();
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

      final results = await Future.wait([
        db.getTotalSalesForDate(now),
        db.getInvoiceCountForDate(now),
        db.getTotalSalesThisMonth(),
        db.getTotalPurchasesThisMonth(),
        db.getCustomerCount(),
        db.getCashBalance(),
        db.getRecentInvoices(limit: 5),
      ]);

      if (mounted) {
        setState(() {
          _todaySales = (results[0] as num?)?.toDouble() ?? 0.0;
          _todayInvoiceCount = (results[1] as num?)?.toInt() ?? 0;
          _monthSales = (results[2] as num?)?.toDouble() ?? 0.0;
          _monthPurchases = (results[3] as num?)?.toDouble() ?? 0.0;
          _customerCount = (results[4] as num?)?.toInt() ?? 0;
          _cashBalance = (results[5] as num?)?.toDouble() ?? 0.0;
          _recentInvoices = (results[6] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ── All service actions combined into one list ────────────────
  List<_QuickActionData> get _allServices => [
    _QuickActionData(label: 'فاتورة بيع', icon: Icons.receipt, color: AppColors.accentBlue, route: AppConstants.newSaleInvoice),
    _QuickActionData(label: 'فاتورة شراء', icon: Icons.shopping_cart, color: AppColors.accentPink, route: AppConstants.newPurchaseInvoice),
    _QuickActionData(label: 'نقطة البيع', icon: Icons.storefront, color: AppColors.secondaryDark, route: AppConstants.pos),
    _QuickActionData(label: 'العملاء', icon: Icons.people, color: AppColors.accentGreen, route: AppConstants.customers),
    _QuickActionData(label: 'الموردون', icon: Icons.local_shipping, color: AppColors.info, route: AppConstants.suppliers),
    _QuickActionData(label: 'المنتجات', icon: Icons.inventory_2, color: AppColors.accentOrange, route: AppConstants.products),
    _QuickActionData(label: 'المصروفات', icon: Icons.attach_money, color: AppColors.error, route: AppConstants.expenses),
    _QuickActionData(label: 'الفواتير', icon: Icons.receipt_long, color: AppColors.primary, route: AppConstants.invoices),
    _QuickActionData(label: 'الصناديق', icon: Icons.account_balance_wallet, color: AppColors.accentGreen, route: AppConstants.cashBoxes),
    _QuickActionData(label: 'دليل الحسابات', icon: Icons.pie_chart, color: AppColors.primaryLight, route: AppConstants.chartOfAccounts),
    _QuickActionData(label: 'التقارير', icon: Icons.bar_chart, color: AppColors.primary, route: AppConstants.reports),
    _QuickActionData(label: 'الإحصائيات', icon: Icons.show_chart, color: const Color(0xFF7B1FA2), route: AppConstants.statistics),
    _QuickActionData(label: 'الموظفين', icon: Icons.person, color: AppColors.warning, route: AppConstants.employees),
    _QuickActionData(label: 'المستودعات', icon: Icons.warehouse, color: AppColors.secondaryDark, route: AppConstants.warehouses),
    _QuickActionData(label: 'العملات', icon: Icons.monetization_on, color: AppColors.success, route: AppConstants.currencies),
    _QuickActionData(label: 'الإعدادات', icon: Icons.settings, color: AppColors.textSecondary, route: AppConstants.settings),
    _QuickActionData(label: 'الدعم الفني', icon: Icons.headset, color: AppColors.warning, route: AppConstants.support),
  ];

  // 6 items per page (3 columns x 2 rows)
  int get _itemsPerPage => 6;
  int get _pageCount => (_allServices.length / _itemsPerPage).ceil();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Gradient Header ──────────────────────────────────
            SliverToBoxAdapter(child: _buildHeader(context, isDark)),

            // ── Pageable Services Grid ────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 100),
                child: _buildPageableServices(context, isDark),
              ),
            ),

            // ── Statistics ───────────────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 300),
                child: _buildSectionTitle(context, 'الإحصائيات'),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 350),
                child: _buildStatCards(context, isDark),
              ),
            ),

            // ── Recent transactions ──────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 400),
                child: _buildSectionTitle(context, 'آخر المعاملات'),
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
  //  GRADIENT HEADER with animations & glassmorphism
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
        DesignSystem.spacing20,
        MediaQuery.of(context).padding.top + DesignSystem.spacing16,
        DesignSystem.spacing20,
        DesignSystem.spacing28,
      ),
      decoration: DesignSystem.headerGradientDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar with animated entry ──────────────────────────
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _headerEntryController,
              curve: Curves.fastOutSlowIn,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.15),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _headerEntryController,
                curve: Curves.fastOutSlowIn,
              )),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Greeting with waving hand
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Animated waving hand
                            AnimatedBuilder(
                              animation: _waveController,
                              builder: (context, child) {
                                return Transform.rotate(
                                  angle: _waveController.value * 0.4 - 0.2,
                                  child: child,
                                );
                              },
                              child: const Text(
                                '👋',
                                style: TextStyle(fontSize: 24),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                greeting,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action icons
                  Row(
                    children: [
                      _HeaderIconButton(
                        icon: Icons.chat,
                        onTap: () {},
                      ),
                      _HeaderIconButton(
                        icon: Icons.notifications,
                        onTap: () {},
                      ),
                      _HeaderIconButton(
                        icon: Icons.list,
                        onTap: () => Scaffold.of(context).openEndDrawer(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DesignSystem.spacing20),

          // ── Today's sales summary card with glassmorphism ──────
          AnimatedBuilder(
            animation: _headerEntryController,
            builder: (context, child) {
              final progress = Curves.fastOutSlowIn.transform(
                _headerEntryController.value,
              );
              return FadeTransition(
                opacity: AlwaysStoppedAnimation(progress),
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - progress)),
                  child: child,
                ),
              );
            },
            child: ClipRRect(
              borderRadius: DesignSystem.asymmetricTopRight(
                large: 50,
                small: 14,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.13),
                    borderRadius: DesignSystem.asymmetricTopRight(
                      large: 50,
                      small: 14,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Sales icon with gradient circle + pulse
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale =
                              1.0 + _pulseController.value * 0.08;
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.secondary,
                                AppColors.secondaryLight,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondary
                                    .withValues(alpha: 0.3),
                                offset: const Offset(0, 4),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.show_chart,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignSystem.spacing16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إجمالي مبيعات اليوم',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Count-up animation for today's sales
                            _CountUpText(
                              value: _todaySales,
                              style: theme.textTheme.titleLarge!.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              isLoading: _isLoading,
                            ),
                          ],
                        ),
                      ),
                      // Invoice count badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$_todayInvoiceCount',
                              style:
                                  theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              'فاتورة',
                              style:
                                  theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SECTION TITLE
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignSystem.spacing20,
        DesignSystem.spacing20,
        DesignSystem.spacing20,
        DesignSystem.spacing8,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: DesignSystem.spacing8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  PAGEABLE SERVICES GRID with staggered animations
  // ══════════════════════════════════════════════════════════════════
  Widget _buildPageableServices(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignSystem.spacing16,
        DesignSystem.spacing16,
        DesignSystem.spacing16,
        0,
      ),
      child: Column(
        children: [
          // ── Section title with animated page indicator ─────────
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: DesignSystem.spacing8),
              Text(
                'الخدمات',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Animated page indicator dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  _pageCount,
                  (index) => AnimatedContainer(
                    duration: DesignSystem.animMedium,
                    curve: Curves.fastOutSlowIn,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacing12),

          // ── PageView of service buttons with staggered animation
          SizedBox(
            height: MediaQuery.of(context).size.width * 0.73,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) =>
                  setState(() => _currentPage = page),
              itemCount: _pageCount,
              itemBuilder: (context, pageIndex) {
                  final startIdx = pageIndex * _itemsPerPage;
                  final endIdx =
                      (startIdx + _itemsPerPage).clamp(0, _allServices.length);
                  final pageItems =
                      _allServices.sublist(startIdx, endIdx);
                  final row1 = pageItems.take(3).toList();
                  final row2 = pageItems.skip(3).take(3).toList();

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        // ── Row 1 with staggered entries ───────────
                        Expanded(
                          child: Row(
                            children: row1
                                .asMap()
                                .entries
                                .map((entry) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                          vertical: 2,
                                        ),
                                        child: _StaggeredServiceButton(
                                          key: ValueKey(
                                            'p${pageIndex}_r0_${entry.key}',
                                          ),
                                          delay: Duration(
                                            milliseconds:
                                                60 * entry.key,
                                          ),
                                          label: entry.value.label,
                                          icon: entry.value.icon,
                                          color: entry.value.color,
                                          onTap: () => AppRouter.push(
                                            context,
                                            entry.value.route,
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        // ── Row 2 with staggered entries ───────────
                        if (row2.isNotEmpty)
                          Expanded(
                            child: Row(
                              children: row2
                                  .asMap()
                                  .entries
                                  .map((entry) => Expanded(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 3,
                                            vertical: 2,
                                          ),
                                          child: _StaggeredServiceButton(
                                            key: ValueKey(
                                              'p${pageIndex}_r1_${entry.key}',
                                            ),
                                            delay: Duration(
                                              milliseconds:
                                                  60 * entry.key + 180,
                                            ),
                                            label: entry.value.label,
                                            icon: entry.value.icon,
                                            color: entry.value.color,
                                            onTap: () => AppRouter.push(
                                              context,
                                              entry.value.route,
                                            ),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                },
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  STATISTICS CARDS (2×2) – redesigned with gradient circles,
  //  count-up animation, progress bars & subtle gradient bg
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStatCards(BuildContext context, bool isDark) {
    final stats = <_StatData>[
      _StatData(
        title: 'إجمالي المبيعات',
        value: _monthSales,
        icon: Icons.show_chart,
        color: AppColors.accentBlue,
        subtitle: 'هذا الشهر',
        isCount: false,
        progress: _monthSales > 0 ? (_monthSales / (_monthSales + _monthPurchases)).clamp(0.0, 1.0) : 0.0,
      ),
      _StatData(
        title: 'إجمالي المشتريات',
        value: _monthPurchases,
        icon: Icons.shopping_cart,
        color: AppColors.accentPink,
        subtitle: 'هذا الشهر',
        isCount: false,
        progress: _monthPurchases > 0 ? (_monthPurchases / (_monthSales + _monthPurchases)).clamp(0.0, 1.0) : 0.0,
      ),
      _StatData(
        title: 'عدد العملاء',
        value: _customerCount.toDouble(),
        icon: Icons.people,
        color: AppColors.accentGreen,
        subtitle: 'إجمالي',
        isCount: true,
        progress: _customerCount > 0 ? (_customerCount / 100).clamp(0.0, 1.0) : 0.0,
      ),
      _StatData(
        title: 'رصيد الصندوق',
        value: _cashBalance,
        icon: Icons.account_balance_wallet,
        color: AppColors.accentOrange,
        subtitle: 'الرصيد الحالي',
        isCount: false,
        progress: _cashBalance > 0 ? 0.7 : 0.0,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSystem.spacing12,
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: DesignSystem.spacing12,
        crossAxisSpacing: DesignSystem.spacing12,
        childAspectRatio: 0.95,
        children: stats.asMap().entries.map((entry) {
          return AnimatedEntry(
            delay: Duration(milliseconds: 120 * entry.key + 200),
            duration: DesignSystem.animEntry,
            offset: 20.0,
            child: _RedesignedStatCard(
              data: entry.value,
              isDark: isDark,
              isLoading: _isLoading,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  RECENT TRANSACTIONS with slide-in & dividers
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
              horizontal: DesignSystem.spacing20,
              vertical: DesignSystem.spacing32,
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt,
                    size: 36,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: DesignSystem.spacing16),
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
                // Slide-in animation for each tile
                AnimatedEntry(
                  delay: Duration(milliseconds: 80 * index),
                  offset: 20.0,
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
                // Subtle divider between items (not after last)
                if (index < _recentInvoices.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignSystem.spacing32,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDark
                          ? AppColors.darkDivider.withValues(alpha: 0.4)
                          : AppColors.divider.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            );
          }

          // "عرض الكل" gradient button
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignSystem.spacing20,
              DesignSystem.spacing12,
              DesignSystem.spacing20,
              DesignSystem.spacing8,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                  ),
                  borderRadius: DesignSystem.borderRadius12,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => AppRouter.push(
                      context,
                      AppConstants.invoices,
                    ),
                    borderRadius: DesignSystem.borderRadius12,
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
                                  letterSpacing: 0,
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

class _QuickActionData {
  const _QuickActionData({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String route;
}

/// Data model for redesigned stat cards.
class _StatData {
  const _StatData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.isCount,
    required this.progress,
  });

  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final String subtitle;
  final bool isCount;
  final double progress;
}

// ── Header icon button ────────────────────────────────────────────
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

// ── Staggered service button wrapper ─────────────────────────────
/// Wraps a [QuickActionButton] with a fade-in + slide-up animation
/// that plays each time the widget is built (i.e. on page change).
class _StaggeredServiceButton extends StatefulWidget {
  const _StaggeredServiceButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.delay = Duration.zero,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Duration delay;

  @override
  State<_StaggeredServiceButton> createState() =>
      _StaggeredServiceButtonState();
}

class _StaggeredServiceButtonState extends State<_StaggeredServiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignSystem.animEntry,
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.fastOutSlowIn,
      ),
    );

    _slideAnim = Tween<double>(begin: 18.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.fastOutSlowIn,
      ),
    );

    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.fastOutSlowIn,
      ),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
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
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnim,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value),
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
          ),
        );
      },
      child: QuickActionButton(
        label: widget.label,
        icon: widget.icon,
        color: widget.color,
        onTap: widget.onTap,
      ),
    );
  }
}

// ── Count-up text widget ─────────────────────────────────────────
/// Animates a numeric value from 0 to [value] using
/// Curves.fastOutSlowIn for a natural deceleration effect.
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
    if (!widget.isLoading && oldWidget.isLoading) {
      _animation = Tween<double>(begin: 0, end: widget.value).animate(
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

// ── Redesigned stat card ─────────────────────────────────────────
/// A modern statistics card with:
/// - Larger icon with gradient background **circle** (fitness-app style)
/// - Prominent value with count-up animation
/// - Subtle progress bar showing percentage of target
/// - Card background with very subtle gradient
class _RedesignedStatCard extends StatefulWidget {
  const _RedesignedStatCard({
    required this.data,
    required this.isDark,
    required this.isLoading,
  });

  final _StatData data;
  final bool isDark;
  final bool isLoading;

  @override
  State<_RedesignedStatCard> createState() => _RedesignedStatCardState();
}

class _RedesignedStatCardState extends State<_RedesignedStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _countUpController;
  late Animation<double> _countUpAnimation;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();

    // Count-up animation
    _countUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _countUpAnimation = Tween<double>(
      begin: 0,
      end: widget.data.value,
    ).animate(
      CurvedAnimation(
        parent: _countUpController,
        curve: Curves.fastOutSlowIn,
      ),
    );

    // Progress bar animation
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _progressAnimation = Tween<double>(
      begin: 0,
      end: widget.data.progress,
    ).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: Curves.fastOutSlowIn,
      ),
    );

    if (!widget.isLoading) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _countUpController.forward();
          _progressController.forward();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RedesignedStatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isLoading && oldWidget.isLoading) {
      _countUpAnimation = Tween<double>(
        begin: 0,
        end: widget.data.value,
      ).animate(
        CurvedAnimation(
          parent: _countUpController,
          curve: Curves.fastOutSlowIn,
        ),
      );
      _progressAnimation = Tween<double>(
        begin: 0,
        end: widget.data.progress,
      ).animate(
        CurvedAnimation(
          parent: _progressController,
          curve: Curves.fastOutSlowIn,
        ),
      );
      _countUpController.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _progressController.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _countUpController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.data;
    final isDark = widget.isDark;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            d.color.withValues(alpha: 0.06),
            isDark
                ? AppColors.darkSurface
                : AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: DesignSystem.borderRadius16,
        boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        border: Border.all(
          color: d.color.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: DesignSystem.borderRadius16,
        child: Stack(
          children: [
            // ── Accent bar on the right side (RTL) ──────────────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: d.color.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
            ),

            // ── Card content ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Larger icon with gradient CIRCLE ──────────
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            d.color.withValues(alpha: 0.25),
                            d.color.withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: d.color.withValues(alpha: 0.15),
                            offset: const Offset(0, 4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(d.icon, color: d.color, size: 24),
                    ),
                  ),
                  const Spacer(),

                  // ── Value with count-up animation ─────────────
                  Center(
                    child: AnimatedBuilder(
                      animation: _countUpController,
                      builder: (context, child) {
                        final currentValue = _countUpAnimation.value;
                        return Text(
                          d.isCount
                              ? currentValue.toInt().toString()
                              : CurrencyFormatter.formatCompactWithSymbol(
                                  currentValue,
                                ),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ── Title ─────────────────────────────────────
                  Center(
                    child: Text(
                      d.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Subtitle + animated progress bar ──────────
                  Row(
                    children: [
                      Text(
                        d.subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, _) {
                            return DesignSystem.progressBar(
                              progress: _progressAnimation.value,
                              color: d.color,
                              width: double.infinity,
                              height: 3,
                            );
                          },
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
}
