import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/report_service.dart';
import '../../../data/datasources/repositories/customer_repository.dart';

/// Advanced charts screen with multiple chart types using pure Flutter custom painting.
class AdvancedChartsScreen extends StatefulWidget {
  const AdvancedChartsScreen({super.key});

  @override
  State<AdvancedChartsScreen> createState() => _AdvancedChartsScreenState();
}

class _AdvancedChartsScreenState extends State<AdvancedChartsScreen> {
  // ── Period & currency filters ──────────────────────────────────
  String _selectedPeriod = 'year'; // week, month, year
  String _selectedCurrency = ''; // '' = All
  int _selectedYear = DateTime.now().year;

  // ── Chart data ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _monthlySalesPurchases = [];
  List<Map<String, dynamic>> _revenueExpenseBreakdown = [];
  List<Map<String, dynamic>> _dailySalesTrend = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topCustomerBalances = [];
  List<Map<String, dynamic>> _monthlyCashFlow = [];
  bool _isLoading = true;

  // ── Tooltip state ──────────────────────────────────────────────
  String? _tooltipText;
  Offset? _tooltipPosition;

  @override
  void initState() {
    super.initState();
    _loadChartData();
  }

  Future<void> _loadChartData() async {
    setState(() => _isLoading = true);
    try {
      final reportService = locator<ReportService>();
      final customerRepo = locator<CustomerRepository>();
      final currency = _selectedCurrency.isEmpty ? null : _selectedCurrency;
      final days = _selectedPeriod == 'week'
          ? 7
          : _selectedPeriod == 'month'
              ? 30
              : 365;

      final results = await Future.wait([
        reportService.getMonthlySalesVsPurchases(_selectedYear, currency: currency),
        reportService.getRevenueExpenseBreakdown(_selectedYear, currency: currency),
        reportService.getDailySalesTrend(days, currency: currency),
        reportService.getTopProducts(5, currency: currency),
        customerRepo.getTopCustomerBalances(5),
        reportService.getMonthlyCashFlow(_selectedYear, currency: currency),
      ]);

      if (mounted) {
        setState(() {
          _monthlySalesPurchases = results[0];
          _revenueExpenseBreakdown = results[1];
          _dailySalesTrend = results[2];
          _topProducts = results[3];
          _topCustomerBalances = results[4];
          _monthlyCashFlow = results[5];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _loadChartData,
                color: AppColors.primary,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Filters ────────────────────────────────────
                    SliverToBoxAdapter(child: _buildFilters(context, isDark)),

                    // ── 1. Monthly Sales vs Purchases Bar Chart ───
                    SliverToBoxAdapter(
                      child: _buildChartCard(
                        context,
                        isDark,
                        title: 'المبيعات مقابل المشتريات شهرياً',
                        child: SizedBox(
                          height: 280,
                          child: MonthlyBarChart(
                            data: _monthlySalesPurchases,
                            isDark: isDark,
                            onTooltip: (text, position) {
                              setState(() {
                                _tooltipText = text;
                                _tooltipPosition = position;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    // ── 2. Revenue vs Expenses Donut Chart ─────────
                    SliverToBoxAdapter(
                      child: _buildChartCard(
                        context,
                        isDark,
                        title: 'توزيع الإيرادات والمصروفات',
                        child: SizedBox(
                          height: 300,
                          child: DonutChart(
                            data: _revenueExpenseBreakdown,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ),

                    // ── 3. Daily Sales Trend Line Chart ────────────
                    SliverToBoxAdapter(
                      child: _buildChartCard(
                        context,
                        isDark,
                        title: 'اتجاه المبيعات اليومي',
                        child: SizedBox(
                          height: 260,
                          child: LineChart(
                            data: _dailySalesTrend,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ),

                    // ── 4. Top 5 Products Horizontal Bar Chart ────
                    SliverToBoxAdapter(
                      child: _buildChartCard(
                        context,
                        isDark,
                        title: 'أفضل 5 منتجات مبيعاً',
                        child: SizedBox(
                          height: 250,
                          child: HorizontalBarChart(
                            data: _topProducts,
                            isDark: isDark,
                            labelKey: 'product_name',
                            valueKey: 'total_amount',
                            barColor: AppColors.accentBlue,
                          ),
                        ),
                      ),
                    ),

                    // ── 5. Customer Balance Distribution ───────────
                    SliverToBoxAdapter(
                      child: _buildChartCard(
                        context,
                        isDark,
                        title: 'أرصدة أفضل العملاء',
                        child: SizedBox(
                          height: 250,
                          child: CustomerBalanceChart(
                            data: _topCustomerBalances,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ),

                    // ── 6. Cash Flow Chart ─────────────────────────
                    SliverToBoxAdapter(
                      child: _buildChartCard(
                        context,
                        isDark,
                        title: 'التدفق النقدي الشهري',
                        child: SizedBox(
                          height: 280,
                          child: StackedBarChart(
                            data: _monthlyCashFlow,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  FILTERS
  // ══════════════════════════════════════════════════════════════════
  Widget _buildFilters(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: isDark ? AppColors.darkSurface : AppColors.surface,
      child: Column(
        children: [
          // Period selector
          Row(
            children: [
              Text('الفترة:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'week', label: Text('أسبوع', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'month', label: Text('شهر', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'year', label: Text('سنة', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_selectedPeriod},
                  onSelectionChanged: (v) {
                    setState(() => _selectedPeriod = v.first);
                    _loadChartData();
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(theme.textTheme.labelSmall),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Currency selector + Year
          Row(
            children: [
              Text('العملة:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCurrency.isEmpty ? 'الكل' : _selectedCurrency,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'الكل', child: Text('الكل', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'YER', child: Text('ر.ي', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'SAR', child: Text('ر.س', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'USD', child: Text('\$', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedCurrency = v == 'الكل' ? '' : v!);
                    _loadChartData();
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Year dropdown
              Text('السنة:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<int>(
                  value: _selectedYear,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: List.generate(5, (i) {
                    final y = DateTime.now().year - i;
                    return DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 12)));
                  }),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedYear = v);
                      _loadChartData();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  CHART CARD WRAPPER
  // ══════════════════════════════════════════════════════════════════
  Widget _buildChartCard(BuildContext context, bool isDark, {required String title, required Widget child}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: DesignSystem.borderRadius16,
          boxShadow: DesignSystem.cardShadow(isLight: !isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  1. MONTHLY SALES VS PURCHASES BAR CHART
// ══════════════════════════════════════════════════════════════════════════════
class MonthlyBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;
  final void Function(String?, Offset?)? onTooltip;

  const MonthlyBarChart({super.key, required this.data, required this.isDark, this.onTooltip});

  static const _monthNames = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem('المبيعات', AppColors.accentBlue),
            const SizedBox(width: 24),
            _legendItem('المشتريات', AppColors.accentPink),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: CustomPaint(
            painter: _MonthlyBarPainter(data: data, isDark: isDark),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MonthlyBarPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  _MonthlyBarPainter({required this.data, required this.isDark});

  static const _monthLabels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];

  @override
  void paint(Canvas canvas, Size size) {
    final paintSales = Paint()..color = AppColors.accentBlue.withOpacity(0.85);
    final paintPurchases = Paint()..color = AppColors.accentPink.withOpacity(0.85);
    final gridPaint = Paint()
      ..color = (isDark ? AppColors.darkBorder : AppColors.border).withOpacity(0.5)
      ..strokeWidth = 0.5;
    final textPainter = TextPainter(textDirection: TextDirection.rtl);

    final leftPad = 50.0;
    final rightPad = 10.0;
    final topPad = 10.0;
    final bottomPad = 30.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    // Find max value
    double maxVal = 0;
    for (final d in data) {
      final s = MoneyHelper.readMoney(d['sales']);
      final p = MoneyHelper.readMoney(d['purchases']);
      if (s > maxVal) maxVal = s;
      if (p > maxVal) maxVal = p;
    }
    if (maxVal == 0) maxVal = 1;

    // Draw Y-axis grid lines & labels
    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final val = maxVal * i / 4;
      textPainter.text = TextSpan(
        text: _formatCompact(val),
        style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftPad - textPainter.width - 4, y - textPainter.height / 2));
    }

    // Draw bars
    final groupW = chartW / 12;
    final barW = groupW * 0.3;
    final gap = groupW * 0.05;

    for (int i = 0; i < 12; i++) {
      final monthData = data.length > i ? data[i] : null;
      final sales = monthData != null ? MoneyHelper.readMoney(monthData['sales']) : 0;
      final purchases = monthData != null ? MoneyHelper.readMoney(monthData['purchases']) : 0;

      final x = leftPad + i * groupW + groupW * 0.15;

      // Sales bar
      final salesH = maxVal > 0 ? (sales / maxVal) * chartH : 0.0;
      if (salesH > 0) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, topPad + chartH - salesH, barW, salesH),
          const Radius.circular(3),
        );
        canvas.drawRRect(rrect, paintSales);
      }

      // Purchases bar
      final purchasesH = maxVal > 0 ? (purchases / maxVal) * chartH : 0.0;
      if (purchasesH > 0) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + barW + gap, topPad + chartH - purchasesH, barW, purchasesH),
          const Radius.circular(3),
        );
        canvas.drawRRect(rrect, paintPurchases);
      }

      // Month label
      textPainter.text = TextSpan(
        text: _monthLabels[i],
        style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + barW - textPainter.width / 2, topPad + chartH + 8));
    }
  }

  String _formatCompact(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  2. REVENUE VS EXPENSES DONUT CHART
// ══════════════════════════════════════════════════════════════════════════════
class DonutChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const DonutChart({super.key, required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Text('لا توجد بيانات', style: TextStyle(color: AppColors.textHint)),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: CustomPaint(
            painter: _DonutPainter(data: data, isDark: isDark),
            size: Size.infinite,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _buildLegend(context),
        ),
      ],
    );
  }

  Widget _buildLegend(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.chartColors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.asMap().entries.map((entry) {
        final i = entry.key;
        final d = entry.value;
        final cat = d['category'] as String? ?? '';
        final total = MoneyHelper.readMoney(d['total']);
        final type = d['type'] as String? ?? '';
        final color = colors[i % colors.length];
        final totalAll = data.fold(0.0, (sum, d) => sum + (MoneyHelper.readMoney(d['total'])));
        final pct = totalAll > 0 ? (total / totalAll * 100).toStringAsFixed(1) : '0.0';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cat, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    Text('$pct% - ${CurrencyFormatter.formatCompact(total)}',
                      style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  _DonutPainter({required this.data, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final colors = AppColors.chartColors;
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = min(size.width, size.height) / 2 - 8;
    final innerR = outerR * 0.55;

    final totalAll = data.fold(0.0, (sum, d) => sum + (MoneyHelper.readMoney(d['total'])));
    if (totalAll == 0) return;

    double startAngle = -pi / 2;

    for (int i = 0; i < data.length; i++) {
      final val = MoneyHelper.readMoney(data[i]['total']);
      final sweepAngle = (val / totalAll) * 2 * pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerR - innerR;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: (outerR + innerR) / 2),
        startAngle,
        sweepAngle - 0.02,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }

    // Center text
    final tp = TextPainter(textDirection: TextDirection.rtl);
    tp.text = TextSpan(
      text: CurrencyFormatter.formatCompact(totalAll),
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2 - 6));

    final tp2 = TextPainter(textDirection: TextDirection.rtl);
    tp2.text = TextSpan(
      text: 'الإجمالي',
      style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
    );
    tp2.layout();
    tp2.paint(canvas, Offset(center.dx - tp2.width / 2, center.dy + 6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  3. DAILY SALES TREND LINE CHART
// ══════════════════════════════════════════════════════════════════════════════
class LineChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const LineChart({super.key, required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(data: data, isDark: isDark),
      size: Size.infinite,
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  _LineChartPainter({required this.data, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 50.0;
    final rightPad = 10.0;
    final topPad = 20.0;
    final bottomPad = 30.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final gridPaint = Paint()
      ..color = (isDark ? AppColors.darkBorder : AppColors.border).withOpacity(0.5)
      ..strokeWidth = 0.5;

    final textPainter = TextPainter(textDirection: TextDirection.rtl);

    // Find max/min
    double maxVal = 0;
    double minVal = double.infinity;
    for (final d in data) {
      final v = MoneyHelper.readMoney(d['total']);
      if (v > maxVal) maxVal = v;
      if (v < minVal) minVal = v;
    }
    if (maxVal == 0) maxVal = 1;
    if (minVal == double.infinity) minVal = 0;
    final range = maxVal - minVal;
    final effectiveMax = maxVal + range * 0.1;
    final effectiveMin = (minVal - range * 0.1).clamp(0, double.infinity);
    final effectiveRange = effectiveMax - effectiveMin;
    if (effectiveRange == 0) return;

    // Draw Y grid lines
    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final val = effectiveMin + effectiveRange * i / 4;
      textPainter.text = TextSpan(
        text: _fmt(val),
        style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftPad - textPainter.width - 4, y - textPainter.height / 2));
    }

    if (data.isEmpty) return;

    // Build points
    final points = <Offset>[];
    final stepX = chartW / (data.length > 1 ? data.length - 1 : 1);

    for (int i = 0; i < data.length; i++) {
      final val = MoneyHelper.readMoney(data[i]['total']);
      final x = leftPad + i * stepX;
      final y = topPad + chartH * (1 - (val - effectiveMin) / effectiveRange);
      points.add(Offset(x, y));
    }

    // Gradient fill below line
    if (points.length >= 2) {
      final fillPath = Path()
        ..moveTo(points.first.dx, topPad + chartH)
        ..lineTo(points.first.dx, points.first.dy);

      for (int i = 1; i < points.length; i++) {
        // Smooth curve
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        fillPath.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
      }

      fillPath.lineTo(points.last.dx, topPad + chartH);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withOpacity(0.25),
            AppColors.primary.withOpacity(0.02),
          ],
        ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH));
      canvas.drawPath(fillPath, fillPaint);

      // Line
      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        linePath.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
      }

      final linePaint = Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(linePath, linePaint);
    }

    // Dots
    final dotPaint = Paint()..color = AppColors.primary;
    final dotBorder = Paint()..color = isDark ? AppColors.darkSurface : AppColors.surface;
    for (final p in points) {
      canvas.drawCircle(p, 5, dotBorder);
      canvas.drawCircle(p, 3.5, dotPaint);
    }

    // X-axis date labels (show a few)
    final labelInterval = (data.length / 6).ceil();
    for (int i = 0; i < data.length; i += labelInterval) {
      final dateStr = data[i]['date'] as String? ?? '';
      final parts = dateStr.split('-');
      final label = parts.length >= 3 ? '${parts[2]}/${parts[1]}' : dateStr;
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(points[i].dx - textPainter.width / 2, topPad + chartH + 8));
    }

    // Min/Max labels
    if (data.isNotEmpty) {
      final maxIdx = data.indexWhere((d) => MoneyHelper.readMoney(d['total']) == maxVal);
      if (maxIdx >= 0 && maxIdx < points.length) {
        textPainter.text = TextSpan(
          text: '▲ ${_fmt(maxVal)}',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(points[maxIdx].dx - textPainter.width / 2, points[maxIdx].dy - 16));
      }
    }
  }

  String _fmt(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  4. HORIZONTAL BAR CHART (Top Products)
// ══════════════════════════════════════════════════════════════════════════════
class HorizontalBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;
  final String labelKey;
  final String valueKey;
  final Color barColor;

  const HorizontalBarChart({
    super.key,
    required this.data,
    required this.isDark,
    required this.labelKey,
    required this.valueKey,
    this.barColor = AppColors.accentBlue,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppColors.textHint)));
    }
    return CustomPaint(
      painter: _HorizontalBarPainter(
        data: data,
        isDark: isDark,
        labelKey: labelKey,
        valueKey: valueKey,
        barColor: barColor,
      ),
      size: Size.infinite,
    );
  }
}

class _HorizontalBarPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isDark;
  final String labelKey;
  final String valueKey;
  final Color barColor;

  _HorizontalBarPainter({
    required this.data,
    required this.isDark,
    required this.labelKey,
    required this.valueKey,
    required this.barColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.rtl);
    final leftPad = 100.0;
    final rightPad = 60.0;
    final chartW = size.width - leftPad - rightPad;
    final barH = (size.height - 10) / data.length - 8;

    double maxVal = 0;
    for (final d in data) {
      final v = MoneyHelper.readMoney(d[valueKey]);
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = 1;

    final colors = AppColors.chartColors;

    for (int i = 0; i < data.length; i++) {
      final val = MoneyHelper.readMoney(data[i][valueKey]);
      final label = data[i][labelKey] as String? ?? '';
      final y = 5.0 + i * (barH + 8);
      final barW = maxVal > 0 ? (val / maxVal) * chartW : 0.0;
      final color = colors[i % colors.length];

      // Label
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
        ),
      );
      textPainter.layout(maxWidth: leftPad - 10);
      textPainter.paint(canvas, Offset(leftPad - textPainter.width - 8, y + (barH - textPainter.height) / 2));

      // Bar
      if (barW > 0) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(leftPad, y, barW, barH),
          const Radius.circular(4),
        );
        final paint = Paint()..color = color.withOpacity(0.8);
        canvas.drawRRect(rrect, paint);
      }

      // Value
      textPainter.text = TextSpan(
        text: CurrencyFormatter.formatCompact(val),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftPad + barW + 6, y + (barH - textPainter.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  5. CUSTOMER BALANCE DISTRIBUTION CHART
// ══════════════════════════════════════════════════════════════════════════════
class CustomerBalanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const CustomerBalanceChart({super.key, required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppColors.textHint)));
    }
    return CustomPaint(
      painter: _CustomerBalancePainter(data: data, isDark: isDark),
      size: Size.infinite,
    );
  }
}

class _CustomerBalancePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  _CustomerBalancePainter({required this.data, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.rtl);
    final leftPad = 100.0;
    final rightPad = 60.0;
    final chartW = size.width - leftPad - rightPad;
    final barH = (size.height - 10) / data.length - 8;

    double maxVal = 0;
    for (final d in data) {
      final v = MoneyHelper.readMoney(d['balance']);
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = 1;

    for (int i = 0; i < data.length; i++) {
      final val = MoneyHelper.readMoney(data[i]['balance']);
      final name = data[i]['name'] as String? ?? '';
      final bt = data[i]['balance_type'] as String? ?? 'credit';
      final y = 5.0 + i * (barH + 8);
      final barW = maxVal > 0 ? (val / maxVal) * chartW : 0.0;

      final isDebit = bt == 'debit';
      final color = isDebit ? AppColors.error : AppColors.success;
      final label = isDebit ? 'عليه' : 'له';

      // Name label
      textPainter.text = TextSpan(
        text: name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
        ),
      );
      textPainter.layout(maxWidth: leftPad - 10);
      textPainter.paint(canvas, Offset(leftPad - textPainter.width - 8, y + (barH - textPainter.height) / 2));

      // Bar
      if (barW > 0) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(leftPad, y, barW, barH),
          const Radius.circular(4),
        );
        final paint = Paint()..color = color.withOpacity(0.8);
        canvas.drawRRect(rrect, paint);
      }

      // Value + type label
      textPainter.text = TextSpan(
        text: '${CurrencyFormatter.formatCompact(val)} ($label)',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftPad + barW + 6, y + (barH - textPainter.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  6. STACKED BAR CHART (Cash Flow)
// ══════════════════════════════════════════════════════════════════════════════
class StackedBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const StackedBarChart({super.key, required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem('الوارد', AppColors.success),
            const SizedBox(width: 24),
            _legendItem('الصادر', AppColors.error),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: CustomPaint(
            painter: _StackedBarPainter(data: data, isDark: isDark),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _StackedBarPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  _StackedBarPainter({required this.data, required this.isDark});

  static const _monthLabels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];

  @override
  void paint(Canvas canvas, Size size) {
    final inflowPaint = Paint()..color = AppColors.success.withOpacity(0.8);
    final outflowPaint = Paint()..color = AppColors.error.withOpacity(0.8);
    final gridPaint = Paint()
      ..color = (isDark ? AppColors.darkBorder : AppColors.border).withOpacity(0.5)
      ..strokeWidth = 0.5;
    final textPainter = TextPainter(textDirection: TextDirection.rtl);

    final leftPad = 50.0;
    final rightPad = 10.0;
    final topPad = 10.0;
    final bottomPad = 30.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    // Find max
    double maxVal = 0;
    for (final d in data) {
      final inf = MoneyHelper.readMoney(d['inflow']);
      final out = MoneyHelper.readMoney(d['outflow']);
      if (inf > maxVal) maxVal = inf;
      if (out > maxVal) maxVal = out;
    }
    if (maxVal == 0) maxVal = 1;

    // Y grid
    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final val = maxVal * i / 4;
      textPainter.text = TextSpan(
        text: _fmt(val),
        style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftPad - textPainter.width - 4, y - textPainter.height / 2));
    }

    // Bars
    final groupW = chartW / 12;
    final barW = groupW * 0.35;
    final gap = groupW * 0.05;

    for (int i = 0; i < 12; i++) {
      final monthData = data.length > i ? data[i] : null;
      final inflow = monthData != null ? MoneyHelper.readMoney(monthData['inflow']) : 0;
      final outflow = monthData != null ? MoneyHelper.readMoney(monthData['outflow']) : 0;

      final x = leftPad + i * groupW + groupW * 0.15;

      // Inflow bar
      final inH = maxVal > 0 ? (inflow / maxVal) * chartH : 0.0;
      if (inH > 0) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, topPad + chartH - inH, barW, inH),
          const Radius.circular(3),
        );
        canvas.drawRRect(rrect, inflowPaint);
      }

      // Outflow bar
      final outH = maxVal > 0 ? (outflow / maxVal) * chartH : 0.0;
      if (outH > 0) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + barW + gap, topPad + chartH - outH, barW, outH),
          const Radius.circular(3),
        );
        canvas.drawRRect(rrect, outflowPaint);
      }

      // Month label
      textPainter.text = TextSpan(
        text: _monthLabels[i],
        style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkTextSecondary : AppColors.textHint),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + barW - textPainter.width / 2, topPad + chartH + 8));
    }
  }

  String _fmt(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
