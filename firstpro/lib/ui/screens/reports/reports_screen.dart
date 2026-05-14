import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../widgets/bar_chart_widget.dart';

/// Comprehensive reports and statistics screen for the FirstPro app.
///
/// Layout (all RTL):
/// 1. Filter section – report type, date range, payment status
/// 2. Summary cards row (horizontal scroll)
/// 3. Daily sales bar chart
/// 4. Top products section
/// 5. Recent reports list
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ── Filter state ────────────────────────────────────────────────
  String _selectedReportType = 'المبيعات';
  String _selectedPaymentStatus = 'الكل';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // ── Report type options ─────────────────────────────────────────
  static const List<String> _reportTypes = [
    'المبيعات',
    'المشتريات',
    'الأرباح والخسائر',
    'حركة الصندوق',
    'المخزون',
  ];

  // ── Payment status options ──────────────────────────────────────
  static const List<String> _paymentStatuses = [
    'الكل',
    'مدفوع',
    'غير مدفوع',
    'معلق',
  ];

  // ── Sample daily sales data for the past 7 days ────────────────
  List<BarData> get _dailySalesData {
    final now = DateTime.now();
    const dayLabels = [
      'السبت',
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
    ];
    // Sample values – in production these come from DB
    const sampleValues = [1850.0, 2200.0, 1400.0, 3100.0, 2750.0, 3600.0, 1950.0];

    final List<BarData> data = [];
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      // weekday: 1=Mon..7=Sun → map to our labels array (0=Sat..6=Fri)
      int labelIndex;
      if (date.weekday == 6) {
        labelIndex = 0; // Saturday
      } else if (date.weekday == 7) {
        labelIndex = 1; // Sunday
      } else {
        labelIndex = date.weekday + 1; // Mon=2..Fri=6
      }
      data.add(BarData(
        label: dayLabels[labelIndex],
        value: sampleValues[6 - i],
      ));
    }
    return data;
  }

  // ── Sample top products ─────────────────────────────────────────
  static const List<_TopProduct> _topProducts = [
    _TopProduct(name: 'قلم حبر أزرق', quantity: 320, revenue: 1920.0),
    _TopProduct(name: 'دفتر A4', quantity: 245, revenue: 3675.0),
    _TopProduct(name: 'حبر طابعة HP', quantity: 180, revenue: 5400.0),
    _TopProduct(name: 'ورق طباعة A4', quantity: 150, revenue: 2250.0),
    _TopProduct(name: 'مجلد بلاستيك', quantity: 120, revenue: 720.0),
  ];

  // ── Sample recent reports ───────────────────────────────────────
  List<_RecentReport> get _recentReports {
    final now = DateTime.now();
    return [
      _RecentReport(
        icon: Icons.today_outlined,
        title: 'التقرير اليومي',
        subtitle: DateFormatter.formatDate(now),
        color: AppColors.primary,
      ),
      _RecentReport(
        icon: Icons.calendar_view_week_outlined,
        title: 'تقرير المبيعات الأسبوعي',
        subtitle: DateFormatter.formatDate(now.subtract(const Duration(days: 7))),
        color: AppColors.info,
      ),
      _RecentReport(
        icon: Icons.account_balance_outlined,
        title: 'تقرير الأرباح والخسائر',
        subtitle: DateFormatter.formatDate(now.subtract(const Duration(days: 14))),
        color: AppColors.secondaryDark,
      ),
      _RecentReport(
        icon: Icons.scale_outlined,
        title: 'ميزان المراجعة',
        subtitle: DateFormatter.formatDate(now.subtract(const Duration(days: 30))),
        color: AppColors.warning,
      ),
    ];
  }

  // ════════════════════════════════════════════════════════════════
  //  DATE PICKERS
  // ════════════════════════════════════════════════════════════════
  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _dateFrom = picked);
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _dateTo = picked);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير والإحصائيات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'طباعة',
            onPressed: () {
              // TODO: Implement report printing
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'مشاركة',
            onPressed: () {
              // TODO: Implement report sharing
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Filter section ─────────────────────────────────
            _buildFilterSection(theme, isDark),

            const SizedBox(height: 16),

            // ── Summary cards ──────────────────────────────────
            _buildSummaryCards(theme, isDark),

            const SizedBox(height: 20),

            // ── Chart section ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: BarChartWidget(
                data: _dailySalesData,
                title: 'المبيعات اليومية',
                barColor: AppColors.primary,
                height: 240,
              ),
            ),

            const SizedBox(height: 20),

            // ── Top products ───────────────────────────────────
            _buildTopProductsSection(theme, isDark),

            const SizedBox(height: 20),

            // ── Recent reports ─────────────────────────────────
            _buildRecentReportsSection(theme, isDark),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  FILTER SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildFilterSection(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Report type dropdown ─────────────────────────────
          Text(
            'نوع التقرير',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedReportType,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _reportTypes
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedReportType = value);
              }
            },
          ),
          const SizedBox(height: 12),

          // ── Date range ──────────────────────────────────────
          Text(
            'نطاق التاريخ',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // From date
              Expanded(
                child: InkWell(
                  onTap: _pickDateFrom,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          _dateFrom != null
                              ? DateFormatter.formatDate(_dateFrom!)
                              : 'من تاريخ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _dateFrom != null
                                ? null
                                : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // To date
              Expanded(
                child: InkWell(
                  onTap: _pickDateTo,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          _dateTo != null
                              ? DateFormatter.formatDate(_dateTo!)
                              : 'إلى تاريخ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _dateTo != null
                                ? null
                                : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Payment status dropdown ──────────────────────────
          Text(
            'حالة الدفع',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedPaymentStatus,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _paymentStatuses
                .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedPaymentStatus = value);
              }
            },
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SUMMARY CARDS (horizontal scroll)
  // ════════════════════════════════════════════════════════════════
  Widget _buildSummaryCards(ThemeData theme, bool isDark) {
    final cards = [
      _SummaryCardData(
        title: 'إجمالي الإيرادات',
        value: 48250.00,
        icon: Icons.trending_up,
        color: AppColors.success,
        lightBg: AppColors.successLight,
      ),
      _SummaryCardData(
        title: 'إجمالي المصروفات',
        value: 22180.50,
        icon: Icons.trending_down,
        color: AppColors.error,
        lightBg: AppColors.errorLight,
      ),
      _SummaryCardData(
        title: 'صافي الربح',
        value: 26069.50,
        icon: Icons.monetization_on_outlined,
        color: AppColors.secondaryDark,
        lightBg: const Color(0xFFFFF8E1),
      ),
      _SummaryCardData(
        title: 'عدد الفواتير',
        value: 87,
        icon: Icons.receipt_long_outlined,
        color: AppColors.info,
        lightBg: AppColors.infoLight,
        isCount: true,
      ),
    ];

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final card = cards[index];
          return _SummaryCard(card: card, isDark: isDark);
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  TOP PRODUCTS SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildTopProductsSection(ThemeData theme, bool isDark) {
    final maxQuantity = _topProducts.first.quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المنتجات الأكثر مبيعاً',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Column(
              children: _topProducts.asMap().entries.map((entry) {
                final index = entry.key;
                final product = entry.value;
                final progress = product.quantity / maxQuantity;
                return _TopProductTile(
                  rank: index + 1,
                  product: product,
                  progress: progress,
                  isDark: isDark,
                  isLast: index == _topProducts.length - 1,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  RECENT REPORTS SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildRecentReportsSection(ThemeData theme, bool isDark) {
    final reports = _recentReports;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'التقارير الأخيرة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...reports.map((report) => _RecentReportCard(
                report: report,
                isDark: isDark,
                onShow: () {
                  // TODO: Navigate to report detail
                },
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SUMMARY CARD (horizontal card)
// ═══════════════════════════════════════════════════════════════════
class _SummaryCardData {
  const _SummaryCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.lightBg,
    this.isCount = false,
  });

  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final Color lightBg;
  final bool isCount;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.card,
    required this.isDark,
  });

  final _SummaryCardData card;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? card.color.withValues(alpha: 0.15)
            : card.lightBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: card.color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(card.icon, color: card.color, size: 24),
          const SizedBox(height: 10),
          Text(
            card.isCount
                ? card.value.toStringAsFixed(0)
                : CurrencyFormatter.formatCompactWithSymbol(card.value),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: card.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TOP PRODUCT TILE
// ═══════════════════════════════════════════════════════════════════
class _TopProduct {
  const _TopProduct({
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  final String name;
  final int quantity;
  final double revenue;
}

class _TopProductTile extends StatelessWidget {
  const _TopProductTile({
    required this.rank,
    required this.product,
    required this.progress,
    required this.isDark,
    required this.isLast,
  });

  final int rank;
  final _TopProduct product;
  final double progress;
  final bool isDark;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Column(
        children: [
          Row(
            children: [
              // ── Rank badge ────────────────────────────────────
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: rank <= 3
                      ? AppColors.secondary.withValues(alpha: 0.2)
                      : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: rank <= 3
                          ? AppColors.secondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ── Product name + quantity ───────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.quantity} قطعة',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Revenue ───────────────────────────────────────
              Text(
                CurrencyFormatter.format(product.revenue),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Progress bar ─────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                rank <= 3 ? AppColors.secondary : AppColors.primaryLight,
              ),
            ),
          ),

          if (!isLast) const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RECENT REPORT CARD
// ═══════════════════════════════════════════════════════════════════
class _RecentReport {
  const _RecentReport({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _RecentReportCard extends StatelessWidget {
  const _RecentReportCard({
    required this.report,
    required this.isDark,
    required this.onShow,
  });

  final _RecentReport report;
  final bool isDark;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onShow,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Icon ──────────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: report.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(report.icon, color: report.color, size: 22),
              ),
              const SizedBox(width: 12),

              // ── Title + date ─────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Show button ──────────────────────────────────
              FilledButton.tonal(
                onPressed: onShow,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  textStyle: theme.textTheme.labelMedium,
                ),
                child: const Text('عرض'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
