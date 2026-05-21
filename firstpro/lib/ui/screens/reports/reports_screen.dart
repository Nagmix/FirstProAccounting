import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
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
  String _selectedCurrency = 'الكل';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // ── Report type options ─────────────────────────────────────────
  static const List<String> _reportTypes = [
    'المبيعات',
    'المشتريات',
    'الأرباح والخسائر',
    'حركة الصندوق',
    'حركة الحساب',
    'المخزون',
  ];

  // ── Payment status options ──────────────────────────────────────
  static const List<String> _paymentStatuses = [
    'الكل',
    'مدفوع',
    'غير مدفوع',
    'معلق',
  ];

  // ── Currency filter options ──────────────────────────────────
  static const List<String> _currencyOptions = [
    'الكل',
    'ر.ي',
    'ر.س',
    r'$',
  ];

  // ── Real data from DB ──────────────────────────────────────────
  bool _isLoading = true;
  double _totalRevenue = 0.0;
  double _totalExpenses = 0.0;
  double _netProfit = 0.0;
  int _invoiceCount = 0;
  List<BarData> _dailySalesData = [];
  List<_TopProduct> _topProducts = [];
  List<_RecentInvoice> _recentInvoices = [];
  List<Map<String, dynamic>> _accountMovementData = [];

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  // ── Load report data from the database ─────────────────────────
  Future<void> _loadReportData() async {
    final db = await DatabaseHelper().database;

    // Build optional date filter clause
    String dateFilter = '';
    List<dynamic> dateArgs = [];
    if (_dateFrom != null) {
      dateFilter += ' AND created_at >= ?';
      dateArgs.add(_dateFrom!.toIso8601String());
    }
    if (_dateTo != null) {
      // Add one day to include the entire "to" date
      final toDate = _dateTo!.add(const Duration(days: 1));
      dateFilter += ' AND created_at < ?';
      dateArgs.add(toDate.toIso8601String());
    }

    // Build optional currency filter clause
    String currencyFilter = '';
    if (_selectedCurrency != 'الكل') {
      final currencyCode = _selectedCurrency == 'ر.ي' ? 'YER' : (_selectedCurrency == 'ر.س' ? 'SAR' : 'USD');
      currencyFilter = ' AND currency = ?';
      dateArgs.add(currencyCode);
    }

    // Total revenue from sales (non-return)
    final revenueResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND is_return = 0$dateFilter$currencyFilter",
      dateArgs,
    );
    final totalRevenue = (revenueResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Total expenses from purchases
    final expenseResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'purchase' AND is_return = 0$dateFilter$currencyFilter",
      dateArgs,
    );
    final totalExpenses = (expenseResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Net profit
    final netProfit = totalRevenue - totalExpenses;

    // Invoice count (all types, non-return)
    final countResult = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE is_return = 0$dateFilter$currencyFilter",
      dateArgs,
    );
    final invoiceCount = (countResult.first['cnt'] as num?)?.toInt() ?? 0;

    // Daily sales for the last 7 days
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
    final List<BarData> dailySales = [];
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final dayResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND is_return = 0 AND created_at >= ? AND created_at < ?",
        [dayStart.toIso8601String(), dayEnd.toIso8601String()],
      );
      final dayTotal = (dayResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // weekday: 1=Mon..7=Sun → map to our labels array (0=Sat..6=Fri)
      int labelIndex;
      if (date.weekday == 6) {
        labelIndex = 0; // Saturday
      } else if (date.weekday == 7) {
        labelIndex = 1; // Sunday
      } else {
        labelIndex = date.weekday + 1; // Mon=2..Fri=6
      }
      dailySales.add(BarData(
        label: dayLabels[labelIndex],
        value: dayTotal,
      ));
    }

    // Top 5 products by quantity sold
    final topProductsResult = await db.rawQuery('''
      SELECT product_id, product_name,
             SUM(quantity) AS total_quantity,
             SUM(total_price) AS total_revenue
      FROM invoice_items
      GROUP BY product_id
      ORDER BY total_quantity DESC
      LIMIT 5
    ''');
    final List<_TopProduct> topProducts = topProductsResult.map((row) => _TopProduct(
      name: row['product_name'] as String? ?? 'منتج غير معروف',
      quantity: (row['total_quantity'] as num?)?.toInt() ?? 0,
      revenue: (row['total_revenue'] as num?)?.toDouble() ?? 0.0,
    )).toList();

    // Recent invoices (last 5)
    final recentResult = await db.rawQuery('''
      SELECT i.id, i.type, i.total, i.is_return, i.created_at,
        CASE
          WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل')
          WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد')
          ELSE 'بدون عميل'
        END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      ORDER BY i.created_at DESC
      LIMIT 5
    ''');
    final List<_RecentInvoice> recentInvoices = recentResult.map((row) {
      final type = row['type'] as String? ?? 'sale';
      final isReturn = (row['is_return'] as int?) == 1;
      final IconData icon;
      final Color color;
      if (type == 'sale') {
        icon = isReturn ? Icons.undo : Icons.receipt_long_outlined;
        color = isReturn ? AppColors.warning : AppColors.success;
      } else {
        icon = isReturn ? Icons.undo : Icons.shopping_cart_outlined;
        color = isReturn ? AppColors.warning : AppColors.error;
      }
      return _RecentInvoice(
        id: row['id'] as String? ?? '',
        title: type == 'sale'
            ? (isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات')
            : (isReturn ? 'مرتجع مشتريات' : 'فاتورة مشتريات'),
        subtitle: row['entity_name'] as String? ?? '',
        date: row['created_at'] as String? ?? '',
        total: (row['total'] as num?)?.toDouble() ?? 0.0,
        icon: icon,
        color: color,
      );
    }).toList();

    // Account movement data
    List<Map<String, dynamic>> accountMovement = [];
    if (_selectedReportType == 'حركة الحساب') {
      accountMovement = await db.rawQuery('''
        SELECT t.id, t.debit, t.credit, t.description, t.date,
          a.name_ar AS account_name, a.account_code
        FROM transactions t
        JOIN accounts a ON t.account_id = a.id
        ORDER BY t.date DESC
        LIMIT 100
      ''');
    }

    if (mounted) {
      setState(() {
        _totalRevenue = totalRevenue;
        _totalExpenses = totalExpenses;
        _netProfit = netProfit;
        _invoiceCount = invoiceCount;
        _dailySalesData = dailySales;
        _topProducts = topProducts;
        _recentInvoices = recentInvoices;
        _accountMovementData = accountMovement;
        _isLoading = false;
      });
    }
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
      _loadReportData();
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
      _loadReportData();
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
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: () {
              setState(() => _isLoading = true);
              _loadReportData();
            },
          ),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              key: ValueKey(_selectedReportType),
              physics: const ClampingScrollPhysics(),
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

                  // ── Recent invoices ────────────────────────────────
                  _buildRecentInvoicesSection(theme, isDark),

                  const SizedBox(height: 20),

                  // ── Account movement ────────────────────────────────
                  _buildAccountMovementSection(theme, isDark),
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
          const SizedBox(height: 12),

          // ── Currency filter dropdown ───────────────────────
          Text(
            'العملة',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedCurrency,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _currencyOptions
                .map((currency) => DropdownMenuItem(value: currency, child: Text(currency)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedCurrency = value;
                  _isLoading = true;
                });
                _loadReportData();
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
        value: _totalRevenue,
        icon: Icons.trending_up,
        color: AppColors.success,
        lightBg: AppColors.successLight,
      ),
      _SummaryCardData(
        title: 'إجمالي المصروفات',
        value: _totalExpenses,
        icon: Icons.trending_down,
        color: AppColors.error,
        lightBg: AppColors.errorLight,
      ),
      _SummaryCardData(
        title: 'صافي الربح',
        value: _netProfit,
        icon: Icons.monetization_on_outlined,
        color: AppColors.secondaryDark,
        lightBg: const Color(0xFFFFF8E1),
      ),
      _SummaryCardData(
        title: 'عدد الفواتير',
        value: _invoiceCount.toDouble(),
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
    if (_topProducts.isEmpty) {
      return const SizedBox.shrink();
    }

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
                final progress = maxQuantity == 0 ? 0.0 : product.quantity / maxQuantity;
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
  //  ACCOUNT MOVEMENT SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildAccountMovementSection(ThemeData theme, bool isDark) {
    if (_selectedReportType != 'حركة الحساب') return const SizedBox.shrink();

    if (_accountMovementData.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text('لا توجد حركات', style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حركة الحسابات',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  ),
                  columns: [
                    DataColumn(label: Text('الحساب', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('عليه', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('له', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('البيان', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.w700))),
                  ],
                  rows: _accountMovementData.map((row) => DataRow(cells: [
                    DataCell(Text(row['account_name'] as String? ?? '')),
                    DataCell(Text(CurrencyFormatter.format((row['debit'] as num?)?.toDouble() ?? 0.0))),
                    DataCell(Text(CurrencyFormatter.format((row['credit'] as num?)?.toDouble() ?? 0.0))),
                    DataCell(Text(row['description'] as String? ?? '', overflow: TextOverflow.ellipsis)),
                    DataCell(Text(DateFormatter.formatDate(DateTime.tryParse(row['date'] as String? ?? '') ?? DateTime.now()))),
                  ])).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  RECENT INVOICES SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildRecentInvoicesSection(ThemeData theme, bool isDark) {
    if (_recentInvoices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'آخر الفواتير',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._recentInvoices.map((invoice) => _RecentInvoiceCard(
                invoice: invoice,
                isDark: isDark,
                onShow: () {
                  // TODO: Navigate to invoice detail
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
//  RECENT INVOICE CARD
// ═══════════════════════════════════════════════════════════════════
class _RecentInvoice {
  const _RecentInvoice({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.total,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String subtitle;
  final String date;
  final double total;
  final IconData icon;
  final Color color;
}

class _RecentInvoiceCard extends StatelessWidget {
  const _RecentInvoiceCard({
    required this.invoice,
    required this.isDark,
    required this.onShow,
  });

  final _RecentInvoice invoice;
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
                  color: invoice.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(invoice.icon, color: invoice.color, size: 22),
              ),
              const SizedBox(width: 12),

              // ── Title + date ─────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoice.subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // ── Amount ────────────────────────────────────────
              Text(
                CurrencyFormatter.format(invoice.total),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: invoice.color,
                ),
              ),
              const SizedBox(width: 8),

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
