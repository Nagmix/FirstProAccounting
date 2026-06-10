import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/date_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/report_service.dart';

/// شاشة العمليات اليومية - تعرض جميع الحركات المالية ليوم محدد في مكان واحد
/// Daily Operations Screen – shows ALL financial transactions for a specific day
class DailyOperationsScreen extends StatefulWidget {
  const DailyOperationsScreen({super.key});

  @override
  State<DailyOperationsScreen> createState() => _DailyOperationsScreenState();
}

class _DailyOperationsScreenState extends State<DailyOperationsScreen> {
  // ── الحالة ─────────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _operations = [];
  Map<String, double> _summary = {
    'total_sales': 0.0,
    'total_purchases': 0.0,
    'total_receipts': 0.0,
    'total_payments': 0.0,
    'total_expenses': 0.0,
  };

  /// الفلتر المحدد: 0=الكل، 1=فواتير، 2=مصروفات، 3=تحويلات
  int _selectedFilter = 0;

  // ── تسميات الفلاتر ────────────────────────────────────────────
  static const List<String> _filterLabels = [
    'الكل',
    'فواتير',
    'مصروفات',
    'تحويلات',
  ];

  // ── دورة الحياة ───────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── تحميل البيانات ────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final operations =
          await locator<ReportService>().getDailyOperations(_selectedDate);
      final summary =
          await locator<ReportService>().getDailySummary(_selectedDate);

      if (mounted) {
        setState(() {
          _operations = operations;
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── العمليات المفلترة ─────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredOperations {
    switch (_selectedFilter) {
      case 1: // فواتير
        return _operations
            .where((o) =>
                o['type'] == 'sale_invoice' || o['type'] == 'purchase_invoice')
            .toList();
      case 2: // مصروفات
        return _operations.where((o) => o['type'] == 'expense').toList();
      case 3: // تحويلات
        return _operations
            .where((o) =>
                o['type'] == 'cash_transfer' ||
                o['type'] == 'currency_exchange')
            .toList();
      default:
        return _operations;
    }
  }

  // ── منتقي التاريخ ─────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      _loadData();
    }
  }

  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _isLoading = true;
    });
    _loadData();
  }

  void _goToNextDay() {
    final now = DateTime.now();
    if (_selectedDate.isBefore(DateTime(now.year, now.month, now.day))) {
      setState(() {
        _selectedDate = _selectedDate.add(const Duration(days: 1));
        _isLoading = true;
      });
      _loadData();
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  // ── أيقونة ولون نوع العملية ────────────────────────────────────
  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'sale_invoice':
        return Icons.receipt;
      case 'purchase_invoice':
        return Icons.shopping_cart;
      case 'expense':
        return Icons.money_off;
      case 'cash_transfer':
        return Icons.swap_horiz;
      case 'currency_exchange':
        return Icons.currency_exchange;
      default:
        return Icons.article_outlined;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'sale_invoice':
        return AppColors.success; // أخضر
      case 'purchase_invoice':
        return AppColors.error; // أحمر
      case 'expense':
        return const Color(0xFF9C27B0); // بنفسجي
      case 'cash_transfer':
        return const Color(0xFF795548); // بني
      case 'currency_exchange':
        return const Color(0xFF009688); // تركوازي
      default:
        return AppColors.textSecondary;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'sale_invoice':
        return 'فاتورة مبيعات';
      case 'purchase_invoice':
        return 'فاتورة مشتريات';
      case 'expense':
        return 'مصروف';
      case 'cash_transfer':
        return 'تحويل نقدي';
      case 'currency_exchange':
        return 'صرافة عملات';
      default:
        return type;
    }
  }

  String _formatTime(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DailyOperationsScreen._formatTime: $e');
      }
      return isoDate;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  بناء الشاشة
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('العمليات اليومية'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () {
                setState(() => _isLoading = true);
                _loadData();
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // منتقي التاريخ
                    SliverToBoxAdapter(child: _buildDatePicker(theme, isDark)),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),

                    // بطاقات الملخص
                    SliverToBoxAdapter(
                        child: _buildSummaryCards(theme, isDark)),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),

                    // شرائح الفلتر
                    SliverToBoxAdapter(child: _buildFilterChips(theme, isDark)),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),

                    // قائمة العمليات
                    _filteredOperations.isEmpty
                        ? SliverFillRemaining(
                            child: _buildEmptyState(theme),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.only(
                                bottom: 100, left: 12, right: 12),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, index) => _buildOperationCard(
                                  _filteredOperations[index],
                                  theme,
                                  isDark,
                                ),
                                childCount: _filteredOperations.length,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
        // شريط الإجمالي في الأسفل
        bottomNavigationBar:
            _isLoading ? null : _buildBottomTotal(theme, isDark),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  منتقي التاريخ
  // ════════════════════════════════════════════════════════════════
  Widget _buildDatePicker(ThemeData theme, bool isDark) {
    final isToday = _isToday(_selectedDate);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // اليوم السابق
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 28),
            onPressed: _goToPreviousDay,
            tooltip: 'اليوم السابق',
          ),
          // التاريخ المحدد
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    DateFormatter.formatDateLong(_selectedDate),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('اليوم',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          )),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // اليوم التالي
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: _goToNextDay,
            tooltip: 'اليوم التالي',
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  بطاقات الملخص
  // ════════════════════════════════════════════════════════════════
  Widget _buildSummaryCards(ThemeData theme, bool isDark) {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildSummaryCard(
            theme,
            'المبيعات',
            _summary['total_sales'] ?? 0.0,
            AppColors.success, // أخضر
            Icons.receipt,
          ),
          const SizedBox(width: 8),
          _buildSummaryCard(
            theme,
            'المشتريات',
            _summary['total_purchases'] ?? 0.0,
            AppColors.error, // أحمر
            Icons.shopping_cart,
          ),
          const SizedBox(width: 8),
          _buildSummaryCard(
            theme,
            'القبض',
            _summary['total_receipts'] ?? 0.0,
            AppColors.info, // أزرق
            Icons.arrow_downward,
          ),
          const SizedBox(width: 8),
          _buildSummaryCard(
            theme,
            'الصرف',
            _summary['total_payments'] ?? 0.0,
            AppColors.warning, // برتقالي
            Icons.arrow_upward,
          ),
          const SizedBox(width: 8),
          _buildSummaryCard(
            theme,
            'المصروفات',
            _summary['total_expenses'] ?? 0.0,
            const Color(0xFF9C27B0), // بنفسجي
            Icons.money_off,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    String title,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.formatCompactWithSymbol(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textHint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  شرائح الفلتر
  // ════════════════════════════════════════════════════════════════
  Widget _buildFilterChips(ThemeData theme, bool isDark) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: List.generate(_filterLabels.length, (index) {
          final isSelected = _selectedFilter == index;
          final chipColor = isSelected
              ? AppColors.primary
              : (isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary);
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text(
                _filterLabels[index],
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : chipColor,
                ),
              ),
              backgroundColor: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.surfaceVariant,
              selectedColor: AppColors.primary,
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkBorder : AppColors.border),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (_) {
                setState(() => _selectedFilter = index);
              },
            ),
          );
        }),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  بطاقة العملية
  // ════════════════════════════════════════════════════════════════
  Widget _buildOperationCard(
      Map<String, dynamic> operation, ThemeData theme, bool isDark) {
    final type = operation['type'] as String? ?? '';
    final typeLabel = operation['type_label'] as String? ?? _getTypeLabel(type);
    final entityName = operation['entity_name'] as String? ?? '';
    final amount = MoneyHelper.readMoney(operation['amount']);
    final time = _formatTime(operation['time'] as String?);
    final refId = operation['id']?.toString() ?? '';
    final color = _getTypeColor(type);
    final icon = _getTypeIcon(type);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // أيقونة النوع
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            // تفاصيل العملية
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        typeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${refId.length > 8 ? refId.substring(0, 8) : refId}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entityName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // المبلغ والوقت
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(amount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  حالة فارغة
  // ════════════════════════════════════════════════════════════════
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'لا توجد عمليات لهذا اليوم',
              style: TextStyle(fontSize: 16, color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  شريط الإجمالي السفلي
  // ════════════════════════════════════════════════════════════════
  Widget _buildBottomTotal(ThemeData theme, bool isDark) {
    final totalSales = _summary['total_sales'] ?? 0.0;
    final totalPurchases = _summary['total_purchases'] ?? 0.0;
    final totalExpenses = _summary['total_expenses'] ?? 0.0;
    final totalReceipts = _summary['total_receipts'] ?? 0.0;
    final totalPayments = _summary['total_payments'] ?? 0.0;
    // صافي اليوم = (مبيعات + قبض) - (مشتريات + مصروفات + صرف)
    final netDaily = (totalSales + totalReceipts) -
        (totalPurchases + totalExpenses + totalPayments);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('عدد العمليات: ${_operations.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('صافي اليوم',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textHint)),
                ],
              ),
            ),
            Text(
              CurrencyFormatter.formatWithSymbol(netDaily),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: netDaily >= 0 ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
