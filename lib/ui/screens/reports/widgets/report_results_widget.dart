import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'report_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Report Results Area – displays KPI cards, search bar, and
//  sortable data table for loaded report data.
// ═══════════════════════════════════════════════════════════════════

class ReportResultsArea extends StatefulWidget {
  final bool isLoading;
  final bool hasData;
  final List<Map<String, dynamic>> reportRows;
  final Map<String, double> reportTotals;

  const ReportResultsArea({
    super.key,
    required this.isLoading,
    required this.hasData,
    required this.reportRows,
    required this.reportTotals,
  });

  @override
  State<ReportResultsArea> createState() => _ReportResultsAreaState();
}

class _ReportResultsAreaState extends State<ReportResultsArea> {
  int? _sortColumnIndex;
  bool _sortAscending = true;
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredRows {
    if (_searchQuery.isEmpty) return widget.reportRows;
    final q = _searchQuery.toLowerCase();
    return widget.reportRows.where((row) {
      return row.values.any((v) => v.toString().toLowerCase().contains(q));
    }).toList();
  }

  List<Map<String, dynamic>> get _sortedRows {
    final rows = List<Map<String, dynamic>>.from(_filteredRows);
    if (_sortColumnIndex == null) return rows;
    final columns = rows.first.keys.toList();
    final sortCol = columns[_sortColumnIndex!];
    rows.sort((a, b) {
      final va = a[sortCol];
      final vb = b[sortCol];
      int cmp;
      if (va is num && vb is num) {
        cmp = va.compareTo(vb);
      } else {
        cmp = va.toString().compareTo(vb.toString());
      }
      return _sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Loading state with shimmer
    if (widget.isLoading) {
      return _ShimmerLoading(isDark: isDark);
    }

    // Report selected but not yet loaded
    if (!widget.hasData) {
      return _EmptyState(
        icon: Icons.filter_list_alt,
        title: 'حدد الفلاتر واضغط "عرض التقرير"',
        subtitle: 'اختر الفترة والعملة ثم اضغط العرض',
        color: AppColors.primary,
      );
    }

    // Loaded but no data
    if (widget.reportRows.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox_outlined,
        title: 'لا توجد بيانات',
        subtitle: 'جرّب تغيير الفلاتر أو اختيار فترة مختلفة',
        color: AppColors.warning,
      );
    }

    // Has data: KPI cards + search + sortable table
    return Column(
      key: const ValueKey('results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI Summary Cards
        if (widget.reportTotals.isNotEmpty) ...[
          _KPICards(totals: widget.reportTotals, isDark: isDark),
          const SizedBox(height: 12),
        ],
        // Search bar
        _SearchBar(
          searchQuery: _searchQuery,
          isDark: isDark,
          onChanged: (val) => setState(() => _searchQuery = val),
          onCleared: () => setState(() => _searchQuery = ''),
        ),
        const SizedBox(height: 8),
        // Sortable data table
        _SortableDataTable(
          reportRows: widget.reportRows,
          filteredRows: _filteredRows,
          sortedRows: _sortedRows,
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          isDark: isDark,
          onSort: (columnIndex, ascending) {
            setState(() {
              _sortColumnIndex = columnIndex;
              _sortAscending = ascending;
            });
          },
        ),
      ],
    );
  }
}

// ── Empty / Illustration State ─────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: color,
            )),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(
              fontSize: 13, color: color.withOpacity(0.6),
            ), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Shimmer Loading ────────────────────────────────────────────

class _ShimmerLoading extends StatelessWidget {
  final bool isDark;

  const _ShimmerLoading({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant;
    final highlightColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return Column(
      children: [
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) => _shimmerBox(baseColor, highlightColor, 140, 80),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(6, (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _shimmerBox(baseColor, highlightColor, double.infinity, 36),
        )),
      ],
    );
  }

  Widget _shimmerBox(Color base, Color highlight, double width, double height) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base.withOpacity(0.3 + value * 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
      onEnd: () {},
    );
  }
}

// ── KPI Summary Cards ─────────────────────────────────────────

class _KPICards extends StatelessWidget {
  final Map<String, double> totals;
  final bool isDark;

  const _KPICards({required this.totals, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = totals.entries
        .where((e) => e.key != 'العدد' && e.key != 'عدد الحسابات' &&
                      e.key != 'عدد الأصناف' && e.key != 'عدد العملاء' &&
                      e.key != 'عدد الصناديق' && e.key != 'العميل' && e.key != 'المورد')
        .take(4)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _KPICard(label: entry.key, value: entry.value, isDark: isDark);
        },
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String label;
  final double value;
  final bool isDark;

  const _KPICard({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color cardColor;
    IconData cardIcon;
    if (label.contains('ربح') || label.contains('إيرادات') || label.contains('مبيعات') ||
        label.contains('البيع') || label.contains('الوارد')) {
      cardColor = value >= 0 ? AppColors.success : AppColors.error;
      cardIcon = value >= 0 ? Icons.trending_up : Icons.trending_down;
    } else if (label.contains('مشتريات') || label.contains('تكلفة') ||
               label.contains('مصروف') || label.contains('دين') || label.contains('متبقي') ||
               label.contains('الصادر') || label.contains('خسائر')) {
      cardColor = AppColors.error;
      cardIcon = Icons.trending_down;
    } else {
      cardColor = AppColors.primary;
      cardIcon = Icons.analytics_outlined;
    }

    final bgColor = cardColor.withOpacity(isDark ? 0.2 : 0.08);
    final borderColor = cardColor.withOpacity(isDark ? 0.4 : 0.3);

    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(cardIcon, size: 16, color: cardColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label, style: theme.textTheme.labelSmall?.copyWith(
                  color: cardColor, fontWeight: FontWeight.w600, fontSize: 10,
                ), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            fmtMoney(value.abs()),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w900, color: cardColor, fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Search Bar ─────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final String searchQuery;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final VoidCallback onCleared;

  const _SearchBar({
    required this.searchQuery,
    required this.isDark,
    required this.onChanged,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'بحث في النتائج...',
        hintStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, fontSize: 13),
        prefixIcon: Icon(Icons.search, size: 20, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear, size: 18, color: AppColors.textHint),
                onPressed: onCleared,
              )
            : null,
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      style: theme.textTheme.bodyMedium,
    );
  }
}

// ── Sortable Data Table ────────────────────────────────────────

class _SortableDataTable extends StatelessWidget {
  final List<Map<String, dynamic>> reportRows;
  final List<Map<String, dynamic>> filteredRows;
  final List<Map<String, dynamic>> sortedRows;
  final int? sortColumnIndex;
  final bool sortAscending;
  final bool isDark;
  final void Function(int, bool) onSort;

  const _SortableDataTable({
    required this.reportRows,
    required this.filteredRows,
    required this.sortedRows,
    this.sortColumnIndex,
    required this.sortAscending,
    required this.isDark,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (filteredRows.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: 'لا توجد نتائج',
        subtitle: 'جرّب كلمة بحث مختلفة',
        color: AppColors.textHint,
      );
    }

    final columns = filteredRows.first.keys.toList();

    // Identify numeric columns
    final numericKeys = <String>{};
    for (final row in reportRows) {
      for (final key in columns) {
        final v = row[key];
        if (v is double || v is int) numericKeys.add(key);
      }
    }

    final dateKeys = {'التاريخ', 'تاريخ الفتح', 'تاريخ الإغلاق'};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: DataTable(
            sortColumnIndex: sortColumnIndex,
            sortAscending: sortAscending,
            headingRowColor: WidgetStateProperty.all(
              AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
            ),
            headingTextStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 11,
            ),
            dataTextStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            columnSpacing: 16,
            horizontalMargin: 12,
            columns: columns.asMap().entries.map((entry) {
              final idx = entry.key;
              final col = entry.value;
              return DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(col, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (sortColumnIndex == idx)
                      Icon(
                        sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14, color: AppColors.primary,
                      ),
                  ],
                ),
                numeric: numericKeys.contains(col),
                onSort: onSort,
              );
            }).toList(),
            rows: sortedRows.map((row) {
              return DataRow(cells: columns.map((col) {
                final v = row[col];
                String display;
                if (v == null) {
                  display = '-';
                } else if (v is double) {
                  if (dateKeys.contains(col)) {
                    display = fmtDate(v.toString());
                  } else if (numericKeys.contains(col) && (col.contains('الكمية') || col.contains('الوارد') || col.contains('الصادر') || col.contains('الصافي') || col.contains('الحد') || col.contains('عدد'))) {
                    display = fmtNum(v);
                  } else if (col.contains('هامش')) {
                    display = '${v.toStringAsFixed(1)}%';
                  } else if (col.contains('سعر الصرف')) {
                    display = v.toStringAsFixed(4);
                  } else {
                    display = fmtMoney(v);
                  }
                } else if (v is int) {
                  display = v.toString();
                } else {
                  final str = v.toString();
                  display = dateKeys.contains(col) ? fmtDate(str) : str;
                }
                // Color negative values in red
                Color? textColor;
                if (v is double && v < 0 && numericKeys.contains(col) && !dateKeys.contains(col)) {
                  textColor = AppColors.error;
                }
                return DataCell(Text(
                  display,
                  style: textColor != null ? TextStyle(color: textColor) : null,
                  textAlign: numericKeys.contains(col) ? TextAlign.left : TextAlign.right,
                ));
              }).toList());
            }).toList(),
          ),
        ),
      ),
    );
  }
}
