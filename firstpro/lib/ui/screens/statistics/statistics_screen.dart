import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../widgets/animated_entry.dart';
import '../../widgets/stat_card.dart';

/// Statistics screen showing detailed financial analytics.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  double _monthSales = 0.0;
  double _monthPurchases = 0.0;
  double _monthExpenses = 0.0;
  // int _customerCount = 0;
  // int _supplierCount = 0;
  double _cashBalance = 0.0;
  List<Map<String, dynamic>> _topCustomers = [];
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _currencyBreakdown = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatisticsData();
  }

  Future<void> _loadStatisticsData() async {
    try {
      final db = DatabaseHelper();

      final results = await Future.wait([
        db.getTotalSalesThisMonth(),
        db.getTotalPurchasesThisMonth(),
        db.getTotalExpensesThisMonth(),
        db.getCustomerCount(),
        db.getCashBalance(),
        db.getRecentInvoices(limit: 5),
      ]);

      // Get supplier count (for potential future use)
      // final suppliers = await db.getAllSuppliers();

      // Get top customers by sales
      final dbInstance = await db.database;
      final now = DateTime.now();
      final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final topCustomersResult = await dbInstance.rawQuery('''
        SELECT c.id, c.name, COALESCE(SUM(i.total), 0.0) AS total_sales
        FROM customers c
        LEFT JOIN invoices i ON i.customer_id = c.id AND i.type = 'sale' AND i.is_return = 0 AND date(i.created_at) >= ?
        GROUP BY c.id
        HAVING total_sales > 0
        ORDER BY total_sales DESC
        LIMIT 5
      ''', [monthStart]);

      // Get currency breakdown
      final currencyBreakdownResult = await dbInstance.rawQuery('''
        SELECT i.currency, COALESCE(SUM(i.total), 0.0) AS total
        FROM invoices i
        WHERE i.is_return = 0 AND date(i.created_at) >= ?
        GROUP BY i.currency
        ORDER BY total DESC
      ''', [monthStart]);

      if (mounted) {
        setState(() {
          _monthSales = results[0] as double;
          _monthPurchases = results[1] as double;
          _monthExpenses = results[2] as double;
          // _customerCount = results[3] as int;
          _cashBalance = results[4] as double;
          _recentActivity = results[5] as List<Map<String, dynamic>>;
          // _supplierCount = suppliers.length;
          _topCustomers = topCustomersResult;
          _currencyBreakdown = currencyBreakdownResult;
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

  double get _netProfit => _monthSales - _monthPurchases - _monthExpenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _loadStatisticsData,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Gradient Header ──────────────────────────────────
            SliverToBoxAdapter(child: _buildHeader(context, isDark)),

            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              )
            else ...[
              // ── Summary Cards ────────────────────────────────────
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 100),
                  child: _buildSectionTitle(context, 'ملخص الشهر'),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 200),
                  child: _buildSummaryCards(context, isDark),
                ),
              ),

              // ── Sales vs Purchases ───────────────────────────────
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 300),
                  child: _buildSectionTitle(context, 'المبيعات مقابل المشتريات'),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 350),
                  child: _buildSalesVsPurchases(context, isDark),
                ),
              ),

              // ── Top Customers ────────────────────────────────────
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 400),
                  child: _buildSectionTitle(context, 'أفضل العملاء'),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 450),
                  child: _buildTopCustomers(context, isDark),
                ),
              ),

              // ── Currency Breakdown ───────────────────────────────
              if (_currencyBreakdown.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: AnimatedEntry(
                    delay: const Duration(milliseconds: 500),
                    child: _buildSectionTitle(context, 'توزيع العملات'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntry(
                    delay: const Duration(milliseconds: 550),
                    child: _buildCurrencyBreakdown(context, isDark),
                  ),
                ),
              ],

              // ── Recent Activity ──────────────────────────────────
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 600),
                  child: _buildSectionTitle(context, 'النشاط الأخير'),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedEntry(
                  delay: const Duration(milliseconds: 650),
                  child: _buildRecentActivity(context, isDark),
                ),
              ),
            ],

            // ── Bottom spacing ───────────────────────────────────
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  GRADIENT HEADER
  // ══════════════════════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateStr =
        '${DateFormatter.dayName(now)}، ${DateFormatter.formatDateLong(now)}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        28,
      ),
      decoration: DesignSystem.headerGradientDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الإحصائيات',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsFill.chartLineUp,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Net profit card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: DesignSystem.asymmetricTopRight(large: 50, small: 14),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _netProfit >= 0
                          ? [AppColors.success, AppColors.successLight]
                          : [AppColors.error, AppColors.errorLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_netProfit >= 0 ? AppColors.success : AppColors.error)
                            .withValues(alpha: 0.3),
                        offset: const Offset(0, 4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    _netProfit >= 0
                        ? PhosphorIconsFill.trendUp
                        : PhosphorIconsFill.trendDown,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صافي الربح هذا الشهر',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(_netProfit.abs()),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _netProfit >= 0 ? 'ربح' : 'خسارة',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
          const SizedBox(width: 8),
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
  //  SUMMARY CARDS (2×2)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSummaryCards(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.1,
        children: [
          StatCard(
            title: 'إجمالي المبيعات',
            value: _monthSales,
            icon: PhosphorIconsFill.chartLineUp,
            color: AppColors.accentBlue,
            subtitle: 'هذا الشهر',
            accentBarColor: AppColors.accentBlue,
          ),
          StatCard(
            title: 'إجمالي المشتريات',
            value: _monthPurchases,
            icon: PhosphorIconsFill.shoppingCart,
            color: AppColors.accentPink,
            subtitle: 'هذا الشهر',
            accentBarColor: AppColors.accentPink,
          ),
          StatCard(
            title: 'إجمالي المصروفات',
            value: _monthExpenses,
            icon: PhosphorIconsFill.currencyDollar,
            color: AppColors.error,
            subtitle: 'هذا الشهر',
            accentBarColor: AppColors.error,
          ),
          StatCard(
            title: 'رصيد الصندوق',
            value: _cashBalance,
            icon: PhosphorIconsFill.vault,
            color: AppColors.accentOrange,
            subtitle: 'الرصيد الحالي',
            accentBarColor: AppColors.accentOrange,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  SALES VS PURCHASES COMPARISON
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSalesVsPurchases(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final total = _monthSales + _monthPurchases;
    final salesPercent = total > 0 ? (_monthSales / total) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: DesignSystem.borderRadius16,
          boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    Expanded(
                      flex: (salesPercent * 100).round().clamp(1, 99),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.accentBlue, AppColors.primaryLight],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - salesPercent) * 100).round().clamp(1, 99),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.accentPink, AppColors.error],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Legend
            Row(
              children: [
                // Sales
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.accentBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المبيعات',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(_monthSales),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Purchases
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.accentPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المشتريات',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(_monthPurchases),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  TOP CUSTOMERS BY SALES
  // ══════════════════════════════════════════════════════════════════
  Widget _buildTopCustomers(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    if (_topCustomers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: DesignSystem.borderRadius16,
            boxShadow: DesignSystem.cardShadow(isLight: !isDark),
          ),
          child: Column(
            children: [
              Icon(
                PhosphorIconsRegular.users,
                size: 36,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 12),
              Text(
                'لا توجد بيانات عملاء بعد',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxSale = _topCustomers.isNotEmpty
        ? (_topCustomers.first['total_sales'] as num?)?.toDouble() ?? 1.0
        : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: DesignSystem.borderRadius16,
          boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        ),
        child: Column(
          children: _topCustomers.asMap().entries.map((entry) {
            final index = entry.key;
            final customer = entry.value;
            final name = customer['name'] as String? ?? '—';
            final sales = (customer['total_sales'] as num?)?.toDouble() ?? 0.0;
            final progress = maxSale > 0 ? sales / maxSale : 0.0;
            final rankColor = index == 0
                ? AppColors.warning
                : index == 1
                    ? AppColors.textSecondary
                    : index == 2
                        ? AppColors.accentOrange
                        : AppColors.primaryLight;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  // Rank badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: rankColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name + bar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.formatCompactWithSymbol(sales),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        DesignSystem.progressBar(
                          progress: progress,
                          color: AppColors.accentBlue,
                          width: double.infinity,
                          height: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  CURRENCY BREAKDOWN
  // ══════════════════════════════════════════════════════════════════
  Widget _buildCurrencyBreakdown(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final currencyNames = {
      'YER': 'ريال يمني',
      'SAR': 'ريال سعودي',
      'USD': 'دولار أمريكي',
    };
    final currencySymbols = {
      'YER': 'ر.ي',
      'SAR': 'ر.س',
      'USD': r'$',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: DesignSystem.borderRadius16,
          boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        ),
        child: Column(
          children: _currencyBreakdown.map((item) {
            final code = item['currency'] as String? ?? 'YER';
            final total = (item['total'] as num?)?.toDouble() ?? 0.0;
            final symbol = currencySymbols[code] ?? code;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        symbol,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currencyNames[code] ?? code,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CurrencyFormatter.format(total, symbol: symbol),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.caretLeft,
                    size: 16,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  RECENT ACTIVITY
  // ══════════════════════════════════════════════════════════════════
  Widget _buildRecentActivity(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    if (_recentActivity.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: DesignSystem.borderRadius16,
            boxShadow: DesignSystem.cardShadow(isLight: !isDark),
          ),
          child: Column(
            children: [
              Icon(
                PhosphorIconsRegular.clockCounterClockwise,
                size: 36,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 12),
              Text(
                'لا يوجد نشاط بعد',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: DesignSystem.borderRadius16,
          boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        ),
        child: Column(
          children: _recentActivity.map((invoice) {
            final type = invoice['type'] as String? ?? 'sale';
            final entityName = invoice['entity_name'] as String? ?? '—';
            final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
            final createdAt = DateTime.tryParse(
                    invoice['created_at'] as String? ?? '') ??
                DateTime.now();
            final isSale = type == 'sale';
            final iconColor = isSale ? AppColors.accentBlue : AppColors.accentPink;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSale
                          ? PhosphorIconsFill.arrowUpRight
                          : PhosphorIconsFill.arrowDownLeft,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entityName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSale ? 'فاتورة بيع' : 'فاتورة شراء',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(total),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSale ? AppColors.accentBlue : AppColors.accentPink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormatter.timeAgo(createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
