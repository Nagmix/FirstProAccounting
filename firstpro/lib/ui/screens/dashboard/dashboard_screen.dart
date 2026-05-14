import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
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
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // TODO: Trigger data refresh
        },
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
                        CurrencyFormatter.format(12580.75),
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
                      '14',
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
        children: const [
          StatCard(
            title: 'إجمالي المبيعات',
            value: 48250.00,
            icon: Icons.shopping_cart_outlined,
            color: AppColors.primary,
            trendPercentage: 12.5,
            trendIsUp: true,
            subtitle: 'هذا الشهر',
          ),
          StatCard(
            title: 'إجمالي المشتريات',
            value: 22180.50,
            icon: Icons.receipt_outlined,
            color: AppColors.info,
            trendPercentage: 3.2,
            trendIsUp: false,
            subtitle: 'هذا الشهر',
          ),
          StatCard(
            title: 'عدد العملاء',
            value: 156,
            icon: Icons.people_outline,
            color: AppColors.secondaryDark,
            trendPercentage: 8.0,
            trendIsUp: true,
            subtitle: 'إجمالي',
          ),
          StatCard(
            title: 'رصيد الصندوق',
            value: 31420.25,
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.accent,
            trendPercentage: 5.7,
            trendIsUp: true,
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
    final transactions = _sampleTransactions();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < transactions.length) {
            final t = transactions[index];
            return TransactionTile(
              customerName: t.customerName,
              amount: t.amount,
              date: t.date,
              status: t.status,
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
        childCount: transactions.length + 1,
      ),
    );
  }

  // ── Sample data (will be replaced with real DB data later) ────
  List<_TransactionSample> _sampleTransactions() {
    final now = DateTime.now();
    return [
      _TransactionSample(
        customerName: 'شركة النور للتجارة',
        amount: 3250.00,
        date: now.subtract(const Duration(hours: 2)),
        status: TransactionStatus.paid,
      ),
      _TransactionSample(
        customerName: 'مؤسسة الأمل',
        amount: 1870.50,
        date: now.subtract(const Duration(hours: 5)),
        status: TransactionStatus.pending,
      ),
      _TransactionSample(
        customerName: 'محلات الرياض',
        amount: 5420.00,
        date: now.subtract(const Duration(days: 1)),
        status: TransactionStatus.paid,
      ),
      _TransactionSample(
        customerName: 'شركة الفجر',
        amount: 980.75,
        date: now.subtract(const Duration(days: 1, hours: 3)),
        status: TransactionStatus.unpaid,
      ),
      _TransactionSample(
        customerName: 'مصنع الخليج',
        amount: 7650.00,
        date: now.subtract(const Duration(days: 2)),
        status: TransactionStatus.paid,
      ),
    ];
  }
}

// ── Internal helper classes ──────────────────────────────────────

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

class _TransactionSample {
  const _TransactionSample({
    required this.customerName,
    required this.amount,
    required this.date,
    required this.status,
  });

  final String customerName;
  final double amount;
  final DateTime date;
  final TransactionStatus status;
}
