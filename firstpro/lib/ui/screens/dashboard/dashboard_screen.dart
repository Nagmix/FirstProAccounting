import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../navigation/app_router.dart';
import '../../widgets/quick_action_button.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/transaction_tile.dart';

/// The main dashboard screen – the first thing the user sees after login.
///
/// Layout (all RTL):
/// 1. Header – greeting + date + today's sales summary
/// 2. Quick-action grid (3 × 3)
/// 3. Statistics cards (2 × 2)
/// 4. Recent transactions list
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ── Dashboard data loaded from database ───────────────────────
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

  /// Loads all dashboard statistics from the database.
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
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header section ─────────────────────────────────
            SliverToBoxAdapter(child: _buildHeader(context, isDark)),

            // ── Quick actions ──────────────────────────────────
            SliverToBoxAdapter(child: _buildSectionTitle(context, 'إجراءات سريعة')),
            SliverToBoxAdapter(child: _buildQuickActions(context)),

            // ── Statistics ─────────────────────────────────────
            SliverToBoxAdapter(child: _buildSectionTitle(context, 'الإحصائيات')),
            SliverToBoxAdapter(child: _buildStatCards(context, isDark)),

            // ── Recent transactions ────────────────────────────
            SliverToBoxAdapter(child: _buildSectionTitle(context, 'آخر المعاملات')),
            _buildRecentTransactions(context, isDark),

            // ── Bottom spacing ─────────────────────────────────
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final greeting = DateFormatter.getGreeting();
    final dateStr =
        '${DateFormatter.dayName(now)}، ${DateFormatter.formatDateLong(now)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(
            greeting,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),

          // Date
          Text(
            dateStr,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),

          // Today's sales summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.point_of_sale,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إجمالي مبيعات اليوم',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'فاتورة',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_todayInvoiceCount',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SECTION TITLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  QUICK ACTIONS (3×3 grid)
  // ══════════════════════════════════════════════════════════════
  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      // Row 1
      _QuickActionData(
        label: 'فاتورة بيع',
        icon: Icons.receipt_long_outlined,
        color: AppColors.primary,
        route: AppRouter.newSaleInvoice,
      ),
      _QuickActionData(
        label: 'فاتورة شراء',
        icon: Icons.assignment_outlined,
        color: AppColors.info,
        route: AppRouter.newPurchaseInvoice,
      ),
      _QuickActionData(
        label: 'نقطة البيع',
        icon: Icons.point_of_sale_outlined,
        color: AppColors.secondaryDark,
        route: AppRouter.pos,
      ),
      // Row 2
      _QuickActionData(
        label: 'إضافة عميل',
        icon: Icons.person_add_outlined,
        color: AppColors.accent,
        route: AppRouter.addCustomer,
      ),
      _QuickActionData(
        label: 'إضافة منتج',
        icon: Icons.add_box_outlined,
        color: AppColors.warning,
        route: AppRouter.addProduct,
      ),
      _QuickActionData(
        label: 'عرض المخزون',
        icon: Icons.warehouse_outlined,
        color: const Color(0xFF7B1FA2),
        route: AppRouter.inventory,
      ),
      // Row 3
      _QuickActionData(
        label: 'التقارير',
        icon: Icons.bar_chart_outlined,
        color: AppColors.info,
        route: AppRouter.reports,
      ),
      _QuickActionData(
        label: 'الإحصائيات',
        icon: Icons.analytics_outlined,
        color: AppColors.primaryLight,
        route: AppRouter.statistics,
      ),
      _QuickActionData(
        label: 'الدعم الفني',
        icon: Icons.support_agent_outlined,
        color: AppColors.error,
        route: AppRouter.support,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 0.85,
        children: actions
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
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  STATISTICS CARDS (2×2)
  // ══════════════════════════════════════════════════════════════
  Widget _buildStatCards(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1.15,
        children: [
          StatCard(
            title: 'إجمالي المبيعات',
            value: _monthSales,
            icon: Icons.shopping_cart_outlined,
            color: AppColors.primary,
            subtitle: 'هذا الشهر',
          ),
          StatCard(
            title: 'إجمالي المشتريات',
            value: _monthPurchases,
            icon: Icons.receipt_outlined,
            color: AppColors.info,
            subtitle: 'هذا الشهر',
          ),
          StatCard(
            title: 'عدد العملاء',
            value: _customerCount.toDouble(),
            icon: Icons.people_outline,
            color: AppColors.secondaryDark,
            isCount: true,
            subtitle: 'إجمالي',
          ),
          StatCard(
            title: 'رصيد الصندوق',
            value: _cashBalance,
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.accent,
            subtitle: 'الرصيد الحالي',
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  RECENT TRANSACTIONS
  // ══════════════════════════════════════════════════════════════
  Widget _buildRecentTransactions(BuildContext context, bool isDark) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_recentInvoices.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 12),
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
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _recentInvoices.length) {
            final invoice = _recentInvoices[index];
            final statusStr = invoice['status'] as String? ?? 'pending';
            final transactionStatus = _mapInvoiceStatus(statusStr);

            return TransactionTile(
              customerName: invoice['entity_name'] as String? ?? '—',
              amount: (invoice['total'] as num?)?.toDouble() ?? 0.0,
              date: DateTime.tryParse(
                      invoice['created_at'] as String? ?? '') ??
                  DateTime.now(),
              status: transactionStatus,
              onTap: () {
                // TODO: Navigate to invoice detail
              },
            );
          }

          // "عرض الكل" button at the end
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => AppRouter.push(context, AppRouter.invoices),
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

  /// Maps a database invoice status string to [TransactionStatus].
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

// ── Internal helper class ────────────────────────────────────────

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
