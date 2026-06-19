import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/ui/screens/reports/trial_balance_screen.dart';
import 'package:firstpro/ui/screens/reports/financial_statements_screen.dart';
import 'package:firstpro/ui/screens/reports/vat_return_screen.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_helpers.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_data_loader.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_card_widget.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_filters_widget.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_results_widget.dart';
import 'package:firstpro/ui/screens/reports/widgets/report_export_button.dart';

// ═══════════════════════════════════════════════════════════════════
//  Reports Screen – Professional Redesign
//  No charts, no auto-loading. User selects report → sets filters →
//  presses "عرض التقرير" to query. Excel export per report.
// ═══════════════════════════════════════════════════════════════════

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

// ── State ───────────────────────────────────────────────────────

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late List<ReportGroup> _groups;
  String? _selectedReportKey;
  bool _isLoading = false;
  bool _hasData = false;

  // Filters
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _selectedCurrency = 'ر.ي';
  int? _selectedAccountId;
  int? _selectedCustomerId;
  int? _selectedSupplierId;
  int? _selectedCashBoxId;
  int? _selectedWarehouseId;
  int? _selectedCategoryId;
  String _selectedAccountType = 'الكل';

  // Report data
  List<Map<String, dynamic>> _reportRows = [];
  Map<String, double> _reportTotals = {};

  // New UI state
  late TabController _tabController;
  DatePreset _selectedDatePreset = DatePreset.thisMonth;

  @override
  void initState() {
    super.initState();
    _initGroups();
    _tabController = TabController(length: _groups.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted) setState(() {});
    });
    _applyDatePreset(_selectedDatePreset);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initGroups() {
    _groups = [
      ReportGroup(
        name: 'المبيعات والمشتريات',
        icon: Icons.swap_horiz,
        color: AppColors.primary,
        isExpanded: true,
        items: [
          const ReportItem(
              name: 'تقرير المبيعات',
              icon: Icons.trending_up,
              color: AppColors.success,
              key: 'sales'),
          const ReportItem(
              name: 'تقرير المشتريات',
              icon: Icons.shopping_cart,
              color: AppColors.error,
              key: 'purchases'),
          const ReportItem(
              name: 'مرتجعات المبيعات',
              icon: Icons.undo,
              color: AppColors.warning,
              key: 'sales_returns'),
          const ReportItem(
              name: 'مرتجعات المشتريات',
              icon: Icons.undo,
              color: AppColors.warning,
              key: 'purchase_returns'),
          const ReportItem(
              name: 'الأرباح والخسائر',
              icon: Icons.assessment,
              color: AppColors.primary,
              key: 'profit_loss'),
          const ReportItem(
              name: 'ربح الفواتير',
              icon: Icons.receipt_long,
              color: AppColors.secondary,
              key: 'invoice_profit'),
          const ReportItem(
              name: 'المبيعات حسب المنتج',
              icon: Icons.inventory,
              color: AppColors.info,
              key: 'sales_by_product'),
          const ReportItem(
              name: 'المبيعات حسب العميل',
              icon: Icons.people,
              color: AppColors.success,
              key: 'sales_by_customer'),
        ],
      ),
      ReportGroup(
        name: 'المحاسبة والمالية',
        icon: Icons.account_balance,
        color: AppColors.info,
        items: [
          const ReportItem(
              name: 'حركة حساب',
              icon: Icons.swap_horiz,
              color: AppColors.info,
              key: 'account_movement'),
          const ReportItem(
              name: 'حركة جميع الحسابات',
              icon: Icons.view_list,
              color: AppColors.info,
              key: 'all_account_movement'),
          const ReportItem(
              name: 'ميزان المراجعة',
              icon: Icons.balance,
              color: AppColors.primary,
              key: 'trial_balance'),
          const ReportItem(
              name: 'ميزان المراجعة (شاشة كاملة)',
              icon: Icons.balance,
              color: AppColors.primary,
              key: 'trial_balance_screen'),
          const ReportItem(
              name: 'إقرار ضريبة القيمة المضافة',
              icon: Icons.receipt_long,
              color: AppColors.secondary,
              key: 'vat_return_screen'),
          const ReportItem(
              name: 'القوائم المالية',
              icon: Icons.account_balance,
              color: AppColors.info,
              key: 'financial_statements'),
          const ReportItem(
              name: 'حركة الصندوق',
              icon: Icons.account_balance_wallet,
              color: AppColors.success,
              key: 'cash_box'),
          const ReportItem(
              name: 'حسابات بدون حركة',
              icon: Icons.block,
              color: AppColors.textHint,
              key: 'accounts_no_movement'),
          const ReportItem(
              name: 'كشف حساب عميل',
              icon: Icons.person,
              color: AppColors.success,
              key: 'customer_statement'),
          const ReportItem(
              name: 'كشف حساب مورد',
              icon: Icons.local_shipping,
              color: AppColors.error,
              key: 'supplier_statement'),
          const ReportItem(
              name: 'تقرير المصروفات',
              icon: Icons.money_off,
              color: AppColors.warning,
              key: 'expenses'),
        ],
      ),
      ReportGroup(
        name: 'المخزون',
        icon: Icons.inventory_2,
        color: AppColors.success,
        items: [
          const ReportItem(
              name: 'تقرير المخزون',
              icon: Icons.inventory_2,
              color: AppColors.success,
              key: 'inventory'),
          const ReportItem(
              name: 'حركة المخزون',
              icon: Icons.swap_vert,
              color: AppColors.primary,
              key: 'inventory_movement'),
          const ReportItem(
              name: 'تكلفة المخزون',
              icon: Icons.attach_money,
              color: AppColors.warning,
              key: 'inventory_cost'),
          const ReportItem(
              name: 'الأصناف المنتهية',
              icon: Icons.warning,
              color: AppColors.error,
              key: 'out_of_stock'),
          const ReportItem(
              name: 'الأصناف قاربت على النفاد',
              icon: Icons.notification_important,
              color: AppColors.warning,
              key: 'low_stock'),
        ],
      ),
      ReportGroup(
        name: 'الديون',
        icon: Icons.people,
        color: AppColors.warning,
        items: [
          const ReportItem(
              name: 'ديون العملاء',
              icon: Icons.people,
              color: AppColors.warning,
              key: 'customer_debts'),
          const ReportItem(
              name: 'ديون الموردين',
              icon: Icons.local_shipping,
              color: AppColors.error,
              key: 'supplier_debts'),
        ],
      ),
      ReportGroup(
        name: 'العمليات',
        icon: Icons.settings,
        color: AppColors.secondary,
        items: [
          const ReportItem(
              name: 'تحويلات الصناديق',
              icon: Icons.swap_horiz,
              color: AppColors.info,
              key: 'cash_transfers'),
          const ReportItem(
              name: 'صرافة العملات',
              icon: Icons.currency_exchange,
              color: AppColors.secondary,
              key: 'currency_exchanges'),
          const ReportItem(
              name: 'السندات',
              icon: Icons.assignment,
              color: AppColors.primary,
              key: 'vouchers'),
          const ReportItem(
              name: 'الورديات',
              icon: Icons.access_time,
              color: AppColors.info,
              key: 'shifts'),
        ],
      ),
    ];
  }

  // ── Date Preset Helper ──────────────────────────────────────

  void _applyDatePreset(DatePreset preset) {
    final result = applyDatePreset(preset);
    setState(() {
      _selectedDatePreset = preset;
      if (result.from != null) _dateFrom = result.from;
      if (result.to != null) _dateTo = result.to;
    });
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _selectedCurrency = 'ر.ي';
      _selectedAccountId = null;
      _selectedCustomerId = null;
      _selectedSupplierId = null;
      _selectedCashBoxId = null;
      _selectedWarehouseId = null;
      _selectedCategoryId = null;
      _selectedAccountType = 'الكل';
      _selectedDatePreset = DatePreset.custom;
    });
  }

  // ── Load Report Data ────────────────────────────────────────

  Future<void> _loadReport() async {
    if (_selectedReportKey == null) return;

    // Validate required filters
    if (_selectedReportKey == 'account_movement' &&
        _selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار الحساب أولاً'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_selectedReportKey == 'customer_statement' &&
        _selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار العميل أولاً'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_selectedReportKey == 'supplier_statement' &&
        _selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار المورد أولاً'),
            backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _hasData = false;
    });
    try {
      final result = await ReportDataLoader.load(
        reportKey: _selectedReportKey!,
        params: ReportFilterParams(
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          selectedCurrency: _selectedCurrency,
          selectedAccountId: _selectedAccountId,
          selectedCustomerId: _selectedCustomerId,
          selectedSupplierId: _selectedSupplierId,
          selectedCashBoxId: _selectedCashBoxId,
          selectedWarehouseId: _selectedWarehouseId,
          selectedCategoryId: _selectedCategoryId,
          selectedAccountType: _selectedAccountType,
        ),
      );
      _reportRows = result.rows;
      _reportTotals = result.totals;
      _hasData = true;
    } catch (e) {
      if (mounted) {
        debugPrint('Report error ($_selectedReportKey): $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'حدث خطأ أثناء تحميل التقرير: ${e.toString().length > 80 ? e.toString().substring(0, 80) + '...' : e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ── Report Selection ────────────────────────────────────────

  void _onReportSelected(ReportItem item) {
    // Navigate to standalone screens for dedicated report views
    if (item.key == 'trial_balance_screen') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const TrialBalanceScreen()));
      return;
    }
    if (item.key == 'financial_statements') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const FinancialStatementsScreen()));
      return;
    }
    if (item.key == 'vat_return_screen') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const VatReturnScreen()));
      return;
    }
    setState(() {
      _selectedReportKey = item.key;
      _hasData = false;
      _reportRows = [];
      _reportTotals = {};
      _clearFilters();
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildSliverAppBar(theme, isDark),
          ],
          body: _buildBody(theme, isDark),
        ),
        floatingActionButton: _hasData && _reportRows.isNotEmpty
            ? ReportExportFab(
                reportRows: _reportRows,
                reportTotals: _reportTotals,
                reportName: getReportName(_selectedReportKey, _groups),
              )
            : null,
      ),
    );
  }

  // ── SliverAppBar with TabBar ──────────────────────────────────

  Widget _buildSliverAppBar(ThemeData theme, bool isDark) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 60,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
      foregroundColor: Colors.white,
      title:
          const Text('التقارير', style: TextStyle(fontWeight: FontWeight.w700)),
      centerTitle: false,
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: AppColors.secondary,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        tabAlignment: TabAlignment.start,
        tabs: _groups
            .map((g) => Tab(
                  icon: Icon(g.icon, size: 18),
                  text: g.name,
                  height: 52,
                ))
            .toList(),
      ),
    );
  }

  // ── Body Content ─────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, bool isDark) {
    return TabBarView(
      controller: _tabController,
      children: _groups.asMap().entries.map((entry) {
        final group = entry.value;
        return _buildTabContent(theme, isDark, group);
      }).toList(),
    );
  }

  Widget _buildTabContent(ThemeData theme, bool isDark, ReportGroup group) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report cards grid
          ReportCardsGrid(
            group: group,
            selectedReportKey: _selectedReportKey,
            onReportSelected: _onReportSelected,
          ),
          // Filters section (only when a report is selected from this group)
          if (_selectedReportKey != null &&
              group.items.any((i) => i.key == _selectedReportKey)) ...[
            const SizedBox(height: 12),
            ReportFiltersSection(
              selectedReportKey: _selectedReportKey,
              selectedDatePreset: _selectedDatePreset,
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              selectedCurrency: _selectedCurrency,
              selectedAccountId: _selectedAccountId,
              selectedCustomerId: _selectedCustomerId,
              selectedSupplierId: _selectedSupplierId,
              selectedCashBoxId: _selectedCashBoxId,
              selectedWarehouseId: _selectedWarehouseId,
              selectedCategoryId: _selectedCategoryId,
              selectedAccountType: _selectedAccountType,
              onDatePresetChanged: _applyDatePreset,
              onDateFromChanged: (v) => setState(() => _dateFrom = v),
              onDateToChanged: (v) => setState(() => _dateTo = v),
              onCurrencyChanged: (v) => setState(() => _selectedCurrency = v),
              onAccountChanged: (v) => setState(() => _selectedAccountId = v),
              onCustomerChanged: (v) => setState(() => _selectedCustomerId = v),
              onSupplierChanged: (v) => setState(() => _selectedSupplierId = v),
              onCashBoxChanged: (v) => setState(() => _selectedCashBoxId = v),
              onWarehouseChanged: (v) =>
                  setState(() => _selectedWarehouseId = v),
              onCategoryChanged: (v) => setState(() => _selectedCategoryId = v),
              onAccountTypeChanged: (v) =>
                  setState(() => _selectedAccountType = v),
            ),
            const SizedBox(height: 12),
            // Load button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadReport,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search, size: 20),
                label: Text(_isLoading ? 'جاري التحميل...' : 'عرض التقرير'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Results area
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: ReportResultsArea(
                key: ValueKey(_selectedReportKey),
                isLoading: _isLoading,
                hasData: _hasData,
                reportRows: _reportRows,
                reportTotals: _reportTotals,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
