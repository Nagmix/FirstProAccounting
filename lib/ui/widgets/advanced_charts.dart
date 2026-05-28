import 'package:fl_chart/fl_chart.dart';
import '../../core/utils/money_helper.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Advanced chart widgets using fl_chart package.
/// Supports line charts, bar charts, and pie charts for financial data visualization.

// ══════════════════════════════════════════════════════════════════
//  LINE CHART - Monthly Revenue Trend
// ══════════════════════════════════════════════════════════════════

class MonthlyRevenueLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const MonthlyRevenueLineChart({
    super.key,
    required this.data,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('لا توجد بيانات كافية')),
      );
    }

    final salesSpots = <FlSpot>[];
    final purchasesSpots = <FlSpot>[];

    for (int i = 0; i < data.length; i++) {
      salesSpots.add(FlSpot(i.toDouble(), MoneyHelper.readMoney(data[i]['sales'])));
      purchasesSpots.add(FlSpot(i.toDouble(), MoneyHelper.readMoney(data[i]['purchases'])));
    }

    return SizedBox(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, left: 6, top: 16, bottom: 8),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: _calculateInterval(data),
              getDrawingHorizontalLine: (value) => FlLine(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                    final month = data[idx]['month'] as String? ?? '';
                    final parts = month.split('-');
                    final monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
                    if (parts.length >= 2) {
                      final m = int.tryParse(parts[1]) ?? 1;
                      final label = m >= 1 && m <= 12 ? monthNames[m - 1] : month;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(label, style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black45)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      _formatCompact(value),
                      style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black45),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: salesSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.accentBlue,
                barWidth: 3,
                dotData: FlDotData(show: data.length <= 12),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.accentBlue.withOpacity(0.1),
                ),
              ),
              LineChartBarData(
                spots: purchasesSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.accentPink,
                barWidth: 3,
                dotData: FlDotData(show: data.length <= 12),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.accentPink.withOpacity(0.1),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (spot) => isDark ? const Color(0xFF2A2A2A) : Colors.white,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final label = spot.barIndex == 0 ? 'مبيعات' : 'مشتريات';
                    return LineTooltipItem(
                      '$label: ${_formatCompact(spot.y)}',
                      TextStyle(
                        color: spot.barIndex == 0 ? AppColors.accentBlue : AppColors.accentPink,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _calculateInterval(List data) {
    double maxVal = 0;
    for (final d in data) {
      final s = MoneyHelper.readMoney(d['sales']);
      final p = MoneyHelper.readMoney(d['purchases']);
      if (s > maxVal) maxVal = s;
      if (p > maxVal) maxVal = p;
    }
    if (maxVal <= 0) return 1000;
    return (maxVal / 4).ceilToDouble();
  }

  String _formatCompact(double value) {
    if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}م';
    if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(0)}ك';
    return value.toStringAsFixed(0);
  }
}

// ══════════════════════════════════════════════════════════════════
//  PIE CHART - Sales by Category
// ══════════════════════════════════════════════════════════════════

class SalesByCategoryPieChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const SalesByCategoryPieChart({
    super.key,
    required this.data,
    required this.isDark,
  });

  static const _chartColors = [
    AppColors.accentBlue,
    AppColors.accentPink,
    AppColors.accentGreen,
    AppColors.accentOrange,
    AppColors.warning,
    AppColors.info,
    AppColors.primary,
    AppColors.success,
    AppColors.error,
    AppColors.secondary,
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('لا توجد بيانات')),
      );
    }

    final total = data.fold<double>(0, (sum, item) => sum + (MoneyHelper.readMoney(item['total'])));
    if (total <= 0) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('لا توجد مبيعات')),
      );
    }

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          // Pie chart
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: data.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final value = MoneyHelper.readMoney(item['total']);
                  final percentage = total > 0 ? (value / total * 100) : 0;
                  final color = _chartColors[idx % _chartColors.length];

                  return PieChartSectionData(
                    value: value,
                    color: color,
                    radius: 50,
                    title: percentage >= 5 ? '${percentage.toStringAsFixed(0)}%' : '',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  );
                }).toList(),
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {},
                ),
              ),
            ),
          ),
          // Legend
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final category = item['category'] as String? ?? '';
                final value = MoneyHelper.readMoney(item['total']);
                final color = _chartColors[idx % _chartColors.length];
                final percentage = total > 0 ? (value / total * 100) : 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$category (${percentage.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  BAR CHART - Daily Sales (last 7 days)
// ══════════════════════════════════════════════════════════════════

class DailySalesBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const DailySalesBarChart({
    super.key,
    required this.data,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('لا توجد بيانات')),
      );
    }

    // Fill in missing days
    final filledData = _fillMissingDays(data);
    double maxVal = 0;
    for (final d in filledData) {
      final v = MoneyHelper.readMoney(d['total']);
      if (v > maxVal) maxVal = v;
    }
    if (maxVal <= 0) maxVal = 1000;

    return SizedBox(
      height: 180,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, left: 6, top: 8, bottom: 8),
        child: BarChart(
          BarChartData(
            maxY: maxVal * 1.2,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxVal / 4,
              getDrawingHorizontalLine: (value) => FlLine(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= filledData.length) return const SizedBox.shrink();
                    final dateStr = filledData[idx]['date'] as String? ?? '';
                    final dayNames = ['أحد', 'إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت'];
                    try {
                      final date = DateTime.parse(dateStr);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          dayNames[date.weekday % 7],
                          style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black45),
                        ),
                      );
                    } catch (_) {
                      return const SizedBox.shrink();
                    }
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      _formatCompact(value),
                      style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black45),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: filledData.asMap().entries.map((entry) {
              final idx = entry.key;
              final value = MoneyHelper.readMoney(entry.value['total']);
              return BarChartGroupData(
                x: idx,
                barRods: [
                  BarChartRodData(
                    toY: value,
                    color: AppColors.accentBlue,
                    width: filledData.length > 7 ? 12 : 20,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxVal * 1.2,
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                    ),
                  ),
                ],
              );
            }).toList(),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (group) => isDark ? const Color(0xFF2A2A2A) : Colors.white,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final dateStr = filledData[groupIndex]['date'] as String? ?? '';
                  return BarTooltipItem(
                    '$dateStr\n${_formatCompact(rod.toY)}',
                    TextStyle(
                      color: AppColors.accentBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _fillMissingDays(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return data;
    final result = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final existing = data.where((d) => d['date'] == dateStr).firstOrNull;
      result.add(existing ?? {'date': dateStr, 'total': 0.0, 'count': 0});
    }
    return result;
  }

  String _formatCompact(double value) {
    if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}م';
    if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(0)}ك';
    return value.toStringAsFixed(0);
  }
}

// ══════════════════════════════════════════════════════════════════
//  PROFIT TREND LINE CHART
// ══════════════════════════════════════════════════════════════════

class ProfitTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isDark;

  const ProfitTrendChart({
    super.key,
    required this.data,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('لا توجد بيانات كافية')),
      );
    }

    final profitSpots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final sales = MoneyHelper.readMoney(data[i]['sales']);
      final purchases = MoneyHelper.readMoney(data[i]['purchases']);
      profitSpots.add(FlSpot(i.toDouble(), sales - purchases));
    }

    double minProfit = 0;
    double maxProfit = 0;
    for (final spot in profitSpots) {
      if (spot.y < minProfit) minProfit = spot.y;
      if (spot.y > maxProfit) maxProfit = spot.y;
    }

    return SizedBox(
      height: 180,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, left: 6, top: 8, bottom: 8),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      _formatCompact(value),
                      style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black45),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minY: minProfit < 0 ? minProfit * 1.2 : 0,
            maxY: maxProfit * 1.2,
            lineBarsData: [
              LineChartBarData(
                spots: profitSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.success,
                barWidth: 3,
                dotData: FlDotData(show: data.length <= 12),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.success.withOpacity(0.08),
                ),
              ),
            ],
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: 0,
                  color: isDark ? Colors.white24 : Colors.black12,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ],
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (spot) => isDark ? const Color(0xFF2A2A2A) : Colors.white,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final label = spot.y >= 0 ? 'ربح' : 'خسارة';
                    return LineTooltipItem(
                      '$label: ${_formatCompact(spot.y)}',
                      TextStyle(
                        color: spot.y >= 0 ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatCompact(double value) {
    if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}م';
    if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(0)}ك';
    return value.toStringAsFixed(0);
  }
}
