import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A single data point for the bar chart.
class BarData {
  const BarData({
    required this.label,
    required this.value,
  });

  /// The label shown below the bar (e.g. Arabic day name).
  final String label;

  /// The numeric value represented by the bar height.
  final double value;
}

/// A simple custom bar chart widget – no external packages required.
///
/// Renders a set of vertical bars with proportional heights, labels below,
/// and values above each bar. Animates on first display.
///
/// Usage:
/// ```dart
/// BarChartWidget(
///   data: [
///     BarData(label: 'السبت', value: 1200),
///     BarData(label: 'الأحد', value: 980),
///     ...
///   ],
/// )
/// ```
class BarChartWidget extends StatefulWidget {
  const BarChartWidget({
    super.key,
    required this.data,
    this.barColor = AppColors.primary,
    this.title,
    this.height = 220,
  });

  /// The data points to render as bars.
  final List<BarData> data;

  /// The fill colour for each bar.
  final Color barColor;

  /// Optional title shown above the chart.
  final String? title;

  /// Total chart height including labels area.
  final double height;

  @override
  State<BarChartWidget> createState() => _BarChartWidgetState();
}

class _BarChartWidgetState extends State<BarChartWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final maxValue = widget.data.isEmpty
        ? 1.0
        : widget.data.map((d) => d.value).reduce((a, b) => a > b ? a : b);

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Optional title ────────────────────────────────────
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Bars ──────────────────────────────────────────────
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return SizedBox(
                height: widget.height - (widget.title != null ? 40 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: widget.data.map((item) {
                    final barHeight = maxValue == 0
                        ? 0.0
                        : (item.value / maxValue) *
                            (widget.height -
                                60 -
                                (widget.title != null ? 40 : 0)) *
                            _animation.value;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // ── Value above bar ──────────────────
                            Text(
                              _formatValue(item.value),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // ── Bar ─────────────────────────────
                            Container(
                              height: barHeight.clamp(0.0, double.infinity),
                              decoration: BoxDecoration(
                                color: widget.barColor.withOpacity(0.85),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ── Label below bar ─────────────────
                            Text(
                              item.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textHint,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
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
            },
          ),
        ],
      ),
    );
  }

  /// Compact value formatter for chart labels.
  String _formatValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }
}
