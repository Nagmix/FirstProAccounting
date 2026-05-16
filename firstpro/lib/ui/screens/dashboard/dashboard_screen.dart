import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../navigation/app_router.dart';
import '../../widgets/animated_entry.dart';
import '../../widgets/quick_action_button.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/transaction_tile.dart';

/// The main dashboard screen – the first thing the user sees.
///
/// Layout (all RTL):
/// 1. Gradient Header – greeting + date + today's sales summary
/// 2. Quick-action grid (3 × 3) with animated entry
/// 3. Statistics cards (2 × 2) with accent bars
/// 4. Recent transactions list
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _todaySales = 0.0;
  int _todayInvoiceCount = 0;
  double _monthSales = 0.0;
  double _monthPurchases = 0.0;
  int _customerCount = 0;
  double _cashBalance = 0.0;
  List<Map<String, dynamic>> _recentInvoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
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
          _todaySales = results[0] as double;
          _todayInvoiceCount = results[1] as int;
          _monthSales = results[2] as double;
          _monthPurchases = results[3] as double;
          _customerCount = results[4] as int;
          _cashBalance = results[5] as double;
          _recentInvoices = results[6] as List<Map<String, dynamic>>;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

            // ── Quick actions ────────────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 100),
                child: _buildSectionTitle(context, 'إجراءات سريعة'),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 200),
                child: _buildQuickActions(context),
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
                delay: const Duration(milliseconds: 400),
                child: _buildStatCards(context, isDark),
              ),
            ),

            // ── Recent transactions ──────────────────────────────
            SliverToBoxAdapter(
              child: AnimatedEntry(
                delay: const Duration(milliseconds: 500),
                child: _buildSectionTitle(context, 'آخر المعاملات'),
              ),
            ),
            _buildRecentTransactions(context, isDark),

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
    final greeting = DateFormatter.getGreeting();
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
          // ── Top bar ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Greeting
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
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

              // Action icons
              Row(
                children: [
                  _HeaderIconButton(
                    icon: PhosphorIconsRegular.whatsappLogo,
                    onTap: () {},
                  ),
                  _HeaderIconButton(
                    icon: PhosphorIconsRegular.bell,
                    onTap: () {},
                  ),
                  _HeaderIconButton(
                    icon: PhosphorIconsRegular.list,
                    onTap: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Today's sales summary card ─────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: DesignSystem.asymmetricTopRight(large: 50, small: 14),
            ),
            child: Row(
              children: [
                // Sales icon with gradient circle
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.secondary, AppColors.secondaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.3),
                        offset: const Offset(0, 4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(
                    PhosphorIconsFill.chartLineUp,
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
                        'إجمالي مبيعات اليوم',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(_todaySales),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                // Invoice count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$_todayInvoiceCount',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'فاتورة',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
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
  //  QUICK ACTIONS - Categorized sections
  // ══════════════════════════════════════════════════════════════════
  Widget _buildQuickActions(BuildContext context) {
    // Main services (always visible on home)
    final mainServices = [
      _QuickActionData(
        label: 'فاتورة بيع',
        icon: PhosphorIconsFill.receipt,
        color: AppColors.accentBlue,
        route: AppConstants.newSaleInvoice,
      ),
      _QuickActionData(
        label: 'فاتورة شراء',
        icon: PhosphorIconsFill.shoppingCart,
        color: AppColors.accentPink,
        route: AppConstants.newPurchaseInvoice,
      ),
      _QuickActionData(
        label: 'نقطة البيع',
        icon: PhosphorIconsFill.storefront,
        color: AppColors.secondaryDark,
        route: AppConstants.pos,
      ),
      _QuickActionData(
        label: 'العملاء',
        icon: PhosphorIconsFill.users,
        color: AppColors.accentGreen,
        route: AppConstants.customers,
      ),
      _QuickActionData(
        label: 'الموردون',
        icon: PhosphorIconsFill.truck,
        color: AppColors.info,
        route: AppConstants.suppliers,
      ),
      _QuickActionData(
        label: 'المنتجات',
        icon: PhosphorIconsFill.package,
        color: AppColors.accentOrange,
        route: AppConstants.products,
      ),
      _QuickActionData(
        label: 'المصروفات',
        icon: PhosphorIconsFill.currencyDollar,
        color: AppColors.error,
        route: AppConstants.expenses,
      ),
      _QuickActionData(
        label: 'الصناديق',
        icon: PhosphorIconsFill.vault,
        color: AppColors.accentGreen,
        route: AppConstants.cashBoxes,
      ),
      _QuickActionData(
        label: 'دليل الحسابات',
        icon: PhosphorIconsFill.chartPie,
        color: AppColors.primaryLight,
        route: AppConstants.chartOfAccounts,
      ),
    ];

    // Financial & Analytics services
    final financialServices = [
      _QuickActionData(
        label: 'التقارير',
        icon: PhosphorIconsFill.chartBar,
        color: AppColors.primary,
        route: AppConstants.reports,
      ),
      _QuickActionData(
        label: 'الإحصائيات',
        icon: PhosphorIconsFill.chartLineUp,
        color: const Color(0xFF7B1FA2),
        route: AppConstants.statistics,
      ),
      _QuickActionData(
        label: 'الموظفين',
        icon: PhosphorIconsFill.user,
        color: AppColors.warning,
        route: AppConstants.employees,
      ),
      _QuickActionData(
        label: 'المستودعات',
        icon: PhosphorIconsFill.warehouse,
        color: AppColors.secondaryDark,
        route: AppConstants.warehouses,
      ),
      _QuickActionData(
        label: 'العملات',
        icon: PhosphorIconsFill.coins,
        color: AppColors.success,
        route: AppConstants.currencies,
      ),
      _QuickActionData(
        label: 'الإعدادات',
        icon: PhosphorIconsFill.gear,
        color: AppColors.textSecondary,
        route: AppConstants.settings,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main services grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: mainServices
                .map(
                  (a) => QuickActionButton(
                    label: a.label,
                    icon: a.icon,
                    color: a.color,
                    onTap: () => AppRouter.push(context, a.route),
                  ),
                )
                .toList(),
          ),

          // Financial & Analytics section title
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'المالية والتحليلات',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Financial services grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: financialServices
                .map(
                  (a) => QuickActionButton(
                    label: a.label,
                    icon: a.icon,
                    color: a.color,
                    onTap: () => AppRouter.push(context, a.route),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  STATISTICS CARDS (2×2)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStatCards(BuildContext context, bool isDark) {
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
            title: 'عدد العملاء',
            value: _customerCount.toDouble(),
            icon: PhosphorIconsFill.users,
            color: AppColors.accentGreen,
            isCount: true,
            subtitle: 'إجمالي',
            accentBarColor: AppColors.accentGreen,
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
  //  RECENT TRANSACTIONS
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
                    PhosphorIconsRegular.receipt,
                    size: 36,
                    color: AppColors.primary,
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

            return AnimatedEntry(
              delay: Duration(milliseconds: 100 * index),
              child: TransactionTile(
                customerName: invoice['entity_name'] as String? ?? '—',
                amount: (invoice['total'] as num?)?.toDouble() ?? 0.0,
                date: DateTime.tryParse(
                        invoice['created_at'] as String? ?? '') ??
                    DateTime.now(),
                status: transactionStatus,
                onTap: () {
                  // TODO: Navigate to invoice detail
                },
              ),
            );
          }

          // "عرض الكل" button
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => AppRouter.push(context, AppConstants.invoices),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('عرض الكل'),
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

// ── Internal helper classes ────────────────────────────────────────

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
