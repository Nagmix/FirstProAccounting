import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/shift_service.dart';

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  List<Map<String, dynamic>> _allShifts = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'open', 'closed'

  // Summary data
  int _openCount = 0;
  int _closedTodayCount = 0;
  double _totalSalesAll = 0.0;

  // Timer for open shift duration
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _openCount > 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final shifts = await locator<ShiftService>().getAllShifts();

      int openCount = 0;
      int closedTodayCount = 0;
      double totalSalesAll = 0.0;
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      for (final s in shifts) {
        final status = (s['status'] as String?) ?? 'closed';
        if (status == 'open') {
          openCount++;
        } else {
          // Count closed today
          final closedAt = s['closed_at'] as String?;
          if (closedAt != null &&
              closedAt.length >= 10 &&
              closedAt.substring(0, 10) == todayStr) {
            closedTodayCount++;
          }
        }
        totalSalesAll += MoneyHelper.readMoney(s['total_sales']);
      }

      if (mounted) {
        setState(() {
          _allShifts = shifts;
          _openCount = openCount;
          _closedTodayCount = closedTodayCount;
          _totalSalesAll = totalSalesAll;
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

  List<Map<String, dynamic>> get _filteredShifts {
    switch (_filter) {
      case 'open':
        return _allShifts
            .where((s) => (s['status'] as String?) == 'open')
            .toList();
      case 'closed':
        return _allShifts
            .where((s) => (s['status'] as String?) != 'open')
            .toList();
      default:
        return _allShifts;
    }
  }

  /// Parse ISO date string safely
  DateTime? _parseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  /// Format shift duration
  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Get currency symbol from currency code
  String _currencySymbol(String? currency) {
    switch (currency) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return '\$';
      default:
        return 'ر.ي';
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الورديات')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // ── Summary header card ──
                    SliverToBoxAdapter(child: _buildSummaryCard()),

                    // ── Filter tabs ──
                    SliverToBoxAdapter(child: _buildFilterTabs()),

                    // ── Shift list ──
                    _filteredShifts.isEmpty
                        ? SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 56,
                                      color: AppColors.textTertiary
                                          .withValues(alpha: 0.5)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _filter == 'open'
                                        ? 'لا توجد ورديات مفتوحة'
                                        : _filter == 'closed'
                                            ? 'لا توجد ورديات مغلقة'
                                            : 'لا توجد ورديات',
                                    style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) => _buildShiftCard(_filteredShifts[i]),
                                childCount: _filteredShifts.length,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SUMMARY HEADER CARD
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _summaryItem(
                icon: Icons.lock_open_outlined,
                label: 'ورديات مفتوحة',
                value: '$_openCount',
                color: AppColors.successLight,
              ),
              _summaryItem(
                icon: Icons.lock_outline,
                label: 'مغلقة اليوم',
                value: '$_closedTodayCount',
                color: AppColors.warningLight,
              ),
              _summaryItem(
                icon: Icons.attach_money,
                label: 'إجمالي المبيعات',
                value:
                    CurrencyFormatter.formatCompactWithSymbol(_totalSalesAll),
                color: AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  FILTER TABS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _filterTab('الكل', 'all'),
          _filterTab('مفتوحة', 'open'),
          _filterTab('مغلقة', 'closed'),
        ],
      ),
    );
  }

  Widget _filterTab(String label, String value) {
    final isActive = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : AppColors.textSecondary,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SHIFT CARD
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildShiftCard(Map<String, dynamic> shift) {
    final isOpen = (shift['status'] as String?) == 'open';
    final currency = (shift['currency'] as String?) ?? 'YER';
    final symbol = _currencySymbol(currency);
    final shiftNumber = shift['shift_number']?.toString() ?? '-';
    final cashBoxName = shift['cash_box_name']?.toString() ?? '-';
    final cashierName = shift['cashier_name']?.toString() ?? '';
    final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);
    final totalSales = MoneyHelper.readMoney(shift['total_sales']);
    final totalReturns = MoneyHelper.readMoney(shift['total_returns']);
    final totalDiscounts = MoneyHelper.readMoney(shift['total_discounts']);
    final expectedAmount = MoneyHelper.readMoney(shift['expected_amount'],
        fallback: openingAmount + totalSales - totalReturns - totalDiscounts);
    final closingAmount = MoneyHelper.readMoney(shift['closing_amount']);
    final difference = MoneyHelper.readMoney(shift['difference']);
    final transactionCount = (shift['transaction_count'] as num?)?.toInt() ?? 0;

    final openedAt = _parseDate(shift['opened_at'] as String?);
    final closedAt = _parseDate(shift['closed_at'] as String?);

    // Duration
    Duration? duration;
    if (openedAt != null) {
      duration = isOpen
          ? DateTime.now().difference(openedAt)
          : (closedAt != null ? closedAt.difference(openedAt) : null);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOpen
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showShiftDetail(shift),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ──
                Row(
                  children: [
                    // Status icon
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.textTertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isOpen ? Icons.lock_open_outlined : Icons.lock_outline,
                        color:
                            isOpen ? AppColors.success : AppColors.textTertiary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Shift number & status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'وردية $shiftNumber',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _statusBadge(isOpen),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cashBoxName,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Duration / close time
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (duration != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? AppColors.success.withValues(alpha: 0.08)
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                  color: isOpen
                                      ? AppColors.success
                                      : AppColors.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDuration(duration),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isOpen
                                        ? AppColors.success
                                        : AppColors.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (openedAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormatter.formatDateTime(openedAt),
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textTertiary),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Cashier name if available
                if (cashierName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        cashierName,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── Financial summary row ──
                Row(
                  children: [
                    _financialChip(
                      label: 'المبيعات',
                      value:
                          CurrencyFormatter.format(totalSales, symbol: symbol),
                      color: AppColors.success,
                    ),
                    _financialChip(
                      label: 'الافتتاح',
                      value: CurrencyFormatter.format(openingAmount,
                          symbol: symbol),
                      color: AppColors.primary,
                    ),
                    _financialChip(
                      label: 'المعاملات',
                      value: '$transactionCount',
                      color: AppColors.info,
                      isCount: true,
                    ),
                  ],
                ),

                // ── For closed shifts: show difference ──
                if (!isOpen && closingAmount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: (difference.abs() < 0.005
                              ? AppColors.success
                              : difference > 0
                                  ? AppColors.info
                                  : AppColors.error)
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (difference.abs() < 0.005
                                ? AppColors.success
                                : difference > 0
                                    ? AppColors.info
                                    : AppColors.error)
                            .withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          difference.abs() < 0.005
                              ? Icons.check_circle_outline
                              : difference > 0
                                  ? Icons.add_circle_outline
                                  : Icons.remove_circle_outline,
                          size: 16,
                          color: difference.abs() < 0.005
                              ? AppColors.success
                              : difference > 0
                                  ? AppColors.info
                                  : AppColors.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          difference.abs() < 0.005
                              ? 'الصندوق متوازن'
                              : difference > 0
                                  ? 'فائض ${CurrencyFormatter.format(difference, symbol: symbol)}'
                                  : 'عجز ${CurrencyFormatter.format(difference.abs(), symbol: symbol)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: difference.abs() < 0.005
                                ? AppColors.success
                                : difference > 0
                                    ? AppColors.info
                                    : AppColors.error,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'المتوقع: ${CurrencyFormatter.format(expectedAmount, symbol: symbol)}',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── For open shifts: Close shift button ──
                if (isOpen) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: () => _showCloseShiftDialog(shift),
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text(
                        'إقفال الوردية',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(
                            color: AppColors.error, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.textTertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOpen ? 'مفتوحة' : 'مغلقة',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isOpen ? AppColors.success : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _financialChip({
    required String label,
    required String value,
    required Color color,
    bool isCount = false,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: isCount ? 14 : 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SHIFT DETAIL BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _showShiftDetail(Map<String, dynamic> shift) async {
    final isOpen = (shift['status'] as String?) == 'open';
    final shiftId = shift['id'] as int;
    final currency = (shift['currency'] as String?) ?? 'YER';
    final symbol = _currencySymbol(currency);

    // Load shift invoices
    List<Map<String, dynamic>> invoices = [];
    try {
      invoices = await locator<ShiftService>().getShiftInvoices(shiftId);
    } catch (e) {
      debugPrint('ShiftsScreen._showShiftDetails: $e');
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (dctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(dctx).viewInsets.bottom +
                    MediaQuery.of(dctx).viewPadding.bottom +
                    24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Title row ──
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isOpen
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.textTertiary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isOpen
                              ? Icons.lock_open_outlined
                              : Icons.lock_outline,
                          color: isOpen
                              ? AppColors.success
                              : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تفاصيل الوردية ${shift['shift_number']?.toString() ?? '-'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              isOpen ? 'مفتوحة' : 'مغلقة',
                              style: TextStyle(
                                fontSize: 13,
                                color: isOpen
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Shift info section ──
                  _detailSectionTitle('معلومات الوردية'),
                  _detailRow(
                      'رقم الوردية', shift['shift_number']?.toString() ?? '-'),
                  _detailRow(
                      'الكاشير', shift['cashier_name']?.toString() ?? '-'),
                  _detailRow(
                      'الصندوق', shift['cash_box_name']?.toString() ?? '-'),
                  _detailRow(
                    'العملة',
                    currency == 'SAR'
                        ? 'ريال سعودي ($currency)'
                        : currency == 'USD'
                            ? 'دولار أمريكي ($currency)'
                            : 'ريال يمني ($currency)',
                  ),
                  _detailRow(
                    'وقت الافتتاح',
                    _parseDate(shift['opened_at'] as String?) != null
                        ? DateFormatter.formatDateTime(
                            _parseDate(shift['opened_at'] as String?)!)
                        : '-',
                  ),
                  if (!isOpen)
                    _detailRow(
                      'وقت الإغلاق',
                      _parseDate(shift['closed_at'] as String?) != null
                          ? DateFormatter.formatDateTime(
                              _parseDate(shift['closed_at'] as String?)!)
                          : '-',
                    ),
                  if (shift['notes'] != null &&
                      (shift['notes'] as String).isNotEmpty)
                    _detailRow('ملاحظات', shift['notes'].toString()),

                  const SizedBox(height: 16),

                  // ── Financial summary ──
                  _detailSectionTitle('الملخص المالي'),
                  _detailRow(
                    'رصيد الافتتاح',
                    CurrencyFormatter.format(
                      MoneyHelper.readMoney(shift['opening_amount']),
                      symbol: symbol,
                    ),
                    valueColor: AppColors.primary,
                  ),
                  _detailRow(
                    'إجمالي المبيعات',
                    CurrencyFormatter.format(
                      MoneyHelper.readMoney(shift['total_sales']),
                      symbol: symbol,
                    ),
                    valueColor: AppColors.success,
                  ),
                  _detailRow(
                    'إجمالي المرتجعات',
                    CurrencyFormatter.format(
                      MoneyHelper.readMoney(shift['total_returns']),
                      symbol: symbol,
                    ),
                    valueColor: AppColors.error,
                  ),
                  _detailRow(
                    'إجمالي الخصومات',
                    CurrencyFormatter.format(
                      MoneyHelper.readMoney(shift['total_discounts']),
                      symbol: symbol,
                    ),
                    valueColor: AppColors.warning,
                  ),

                  const Divider(height: 24),

                  // Expected vs Actual
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      children: [
                        _detailRow(
                          'المتوقع في الصندوق',
                          CurrencyFormatter.format(
                            MoneyHelper.readMoney(shift['expected_amount'],
                                fallback: MoneyHelper.readMoney(
                                        shift['opening_amount']) +
                                    MoneyHelper.readMoney(
                                        shift['total_sales']) -
                                    MoneyHelper.readMoney(
                                        shift['total_returns']) -
                                    MoneyHelper.readMoney(
                                        shift['total_discounts'])),
                            symbol: symbol,
                          ),
                          valueColor: AppColors.primary,
                          isBold: true,
                        ),
                        if (!isOpen) ...[
                          const SizedBox(height: 6),
                          _detailRow(
                            'الفعلي في الصندوق',
                            CurrencyFormatter.format(
                              MoneyHelper.readMoney(shift['closing_amount']),
                              symbol: symbol,
                            ),
                            valueColor: AppColors.textPrimary,
                            isBold: true,
                          ),
                          const SizedBox(height: 6),
                          _buildDifferenceRow(shift, symbol),
                        ],
                        const SizedBox(height: 6),
                        _detailRow(
                          'عدد المعاملات',
                          '${(shift['transaction_count'] as num?)?.toInt() ?? 0}',
                        ),
                      ],
                    ),
                  ),

                  // ── Transactions list ──
                  if (invoices.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _detailSectionTitle(
                        'الفواتير خلال الوردية (${invoices.length})'),
                    const SizedBox(height: 8),
                    ...invoices.map((inv) => _buildInvoiceItem(inv, symbol)),
                  ] else ...[
                    const SizedBox(height: 20),
                    _detailSectionTitle('الفواتير خلال الوردية'),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'لا توجد فواتير في هذه الوردية',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 13),
                        ),
                      ),
                    ),
                  ],

                  // ── For closed shifts: Z-Report summary ──
                  if (!isOpen) ...[
                    const SizedBox(height: 20),
                    _detailSectionTitle('تقرير Z - ملخص الإقفال'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        children: [
                          _detailRow(
                              'رصيد الافتتاح',
                              CurrencyFormatter.format(
                                MoneyHelper.readMoney(shift['opening_amount']),
                                symbol: symbol,
                              )),
                          _detailRow(
                              'إجمالي المبيعات',
                              CurrencyFormatter.format(
                                MoneyHelper.readMoney(shift['total_sales']),
                                symbol: symbol,
                              ),
                              valueColor: AppColors.success),
                          _detailRow(
                              'إجمالي المرتجعات',
                              CurrencyFormatter.format(
                                MoneyHelper.readMoney(shift['total_returns']),
                                symbol: symbol,
                              ),
                              valueColor: AppColors.error),
                          _detailRow(
                              'إجمالي الخصومات',
                              CurrencyFormatter.format(
                                MoneyHelper.readMoney(shift['total_discounts']),
                                symbol: symbol,
                              ),
                              valueColor: AppColors.warning),
                          const Divider(height: 20),
                          _detailRow(
                              'المتوقع',
                              CurrencyFormatter.format(
                                MoneyHelper.readMoney(shift['expected_amount']),
                                symbol: symbol,
                              ),
                              isBold: true),
                          _detailRow(
                              'الفعلي',
                              CurrencyFormatter.format(
                                MoneyHelper.readMoney(shift['closing_amount']),
                                symbol: symbol,
                              ),
                              isBold: true),
                          _buildDifferenceRow(shift, symbol),
                        ],
                      ),
                    ),
                  ],

                  // ── For open shifts: Close button ──
                  if (isOpen) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(dctx);
                          _showCloseShiftDialog(shift);
                        },
                        icon: const Icon(Icons.lock_outline, size: 20),
                        label: const Text(
                          'إقفال الوردية',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifferenceRow(Map<String, dynamic> shift, String symbol) {
    final difference = MoneyHelper.readMoney(shift['difference']);
    if (difference.abs() < 0.005) {
      return _detailRow('الفرق', 'متوازن ✓',
          valueColor: AppColors.success, isBold: true);
    }
    final isSurplus = difference > 0;
    return _detailRow(
      'الفرق',
      '${isSurplus ? 'فائض' : 'عجز'} ${CurrencyFormatter.format(difference.abs(), symbol: symbol)}',
      valueColor: isSurplus ? AppColors.info : AppColors.error,
      isBold: true,
    );
  }

  Widget _buildInvoiceItem(Map<String, dynamic> inv, String symbol) {
    final type = (inv['type'] as String?) ?? 'sale';
    final isReturn = (inv['is_return'] as int?) == 1 || type.contains('return');
    final total = MoneyHelper.readMoney(inv['total']);
    final entityName = inv['entity_name']?.toString() ?? '';
    final createdAt = _parseDate(inv['created_at'] as String?);
    final invoiceNumber =
        inv['invoice_number']?.toString() ?? inv['id']?.toString() ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isReturn ? AppColors.error : AppColors.success)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isReturn ? Icons.keyboard_return : Icons.receipt_long_outlined,
              size: 18,
              color: isReturn ? AppColors.error : AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoiceNumber,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                if (entityName.isNotEmpty)
                  Text(
                    entityName,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.format(total, symbol: symbol),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isReturn ? AppColors.error : AppColors.success,
                ),
              ),
              if (createdAt != null)
                Text(
                  DateFormatter.formatTime(createdAt),
                  style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CLOSE SHIFT DIALOG
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _showCloseShiftDialog(Map<String, dynamic> shift) async {
    final shiftId = shift['id'] as int;
    final currency = (shift['currency'] as String?) ?? 'YER';
    final symbol = _currencySymbol(currency);

    final openingAmount = MoneyHelper.readMoney(shift['opening_amount']);
    final totalSales = MoneyHelper.readMoney(shift['total_sales']);
    final totalReturns = MoneyHelper.readMoney(shift['total_returns']);
    final totalDiscounts = MoneyHelper.readMoney(shift['total_discounts']);
    final transactionCount = (shift['transaction_count'] as num?)?.toInt() ?? 0;
    final expectedAmount =
        openingAmount + totalSales - totalReturns - totalDiscounts;

    final closingAmountController =
        TextEditingController(text: expectedAmount.toStringAsFixed(2));
    final notesController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).viewPadding.bottom +
                  24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.lock_outline,
                            color: AppColors.error),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'إقفال الوردية',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Summary
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      children: [
                        _detailRow(
                            'رصيد الافتتاح',
                            CurrencyFormatter.format(openingAmount,
                                symbol: symbol)),
                        _detailRow(
                            'إجمالي المبيعات',
                            CurrencyFormatter.format(totalSales,
                                symbol: symbol),
                            valueColor: AppColors.success),
                        _detailRow(
                            'إجمالي المرتجعات',
                            CurrencyFormatter.format(totalReturns,
                                symbol: symbol),
                            valueColor: AppColors.error),
                        _detailRow(
                            'إجمالي الخصومات',
                            CurrencyFormatter.format(totalDiscounts,
                                symbol: symbol),
                            valueColor: AppColors.warning),
                        const Divider(height: 20),
                        _detailRow(
                            'المتوقع في الصندوق',
                            CurrencyFormatter.format(expectedAmount,
                                symbol: symbol),
                            valueColor: AppColors.primary,
                            isBold: true),
                        _detailRow('عدد المعاملات', '$transactionCount'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Closing amount field
                  Text(
                    'المبلغ الفعلي في الصندوق',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: closingAmountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.payments_outlined),
                      hintText: 'أدخل المبلغ الفعلي',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixText: symbol,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.note_outlined),
                      hintText: 'ملاحظات الإغلاق...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final closingAmount =
                            double.tryParse(closingAmountController.text) ??
                                expectedAmount;
                        final difference = closingAmount - expectedAmount;
                        final now = DateTime.now();
                        final navigator = Navigator.of(ctx);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        try {
                          // Step 1: Post all shift invoices
                          await locator<ShiftService>()
                              .postShiftInvoices(shiftId);

                          // Step 2: Close the shift
                          final closeData = {
                            'closing_amount': closingAmount,
                            'expected_amount': expectedAmount,
                            'difference': difference,
                            'status': 'closed',
                            'closed_at': now.toIso8601String(),
                            'notes': notesController.text.isEmpty
                                ? shift['notes']
                                : notesController.text,
                            'updated_at': now.toIso8601String(),
                          };
                          await locator<ShiftService>()
                              .closeShift(shiftId, closeData);

                          if (!mounted) return;
                          navigator.pop(); // Close bottom sheet

                          // Show result dialog
                          _showCloseResultDialog(expectedAmount, closingAmount,
                              difference, symbol);
                        } catch (e) {
                          if (!mounted) return;
                          navigator.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('حدث خطأ أثناء إقفال الوردية'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.lock_outline),
                      label: const Text(
                        'تأكيد الإقفال',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    closingAmountController.dispose();
    notesController.dispose();
  }

  void _showCloseResultDialog(
    double expectedAmount,
    double closingAmount,
    double difference,
    String symbol,
  ) {
    showDialog(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                difference.abs() < 0.005 ? Icons.check_circle : Icons.warning,
                color: difference.abs() < 0.005
                    ? AppColors.success
                    : AppColors.warning,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Text('تم إغلاق الوردية'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'المتوقع: ${CurrencyFormatter.format(expectedAmount, symbol: symbol)}'),
              Text(
                  'الفعلي: ${CurrencyFormatter.format(closingAmount, symbol: symbol)}'),
              const SizedBox(height: 8),
              if (difference.abs() >= 0.005)
                Text(
                  difference > 0
                      ? 'فائض: ${CurrencyFormatter.format(difference, symbol: symbol)}'
                      : 'عجز: ${CurrencyFormatter.format(difference.abs(), symbol: symbol)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: difference > 0 ? AppColors.success : AppColors.error,
                  ),
                )
              else
                const Text(
                  'الصندوق متوازن',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.success),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dctx);
                _loadData(); // Refresh data
              },
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }
}
