import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import 'create_quotation_screen.dart';

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key});

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allQuotations = [];
  List<Map<String, dynamic>> _filteredQuotations = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _searchQuery = '';
  late TabController _tabController;

  final List<MapEntry<String, String>> _statusTabs = [
    const MapEntry('all', 'الكل'),
    const MapEntry('draft', 'مسودة'),
    const MapEntry('sent', 'مرسل'),
    const MapEntry('accepted', 'مقبول'),
    const MapEntry('rejected', 'مرفوض'),
    const MapEntry('expired', 'منتهي'),
    const MapEntry('converted', 'تم التحويل'),
  ];

  static const Map<String, Color> _statusColors = {
    'draft': Colors.grey,
    'sent': Colors.blue,
    'accepted': Colors.green,
    'rejected': Colors.red,
    'expired': Colors.orange,
    'converted': Colors.purple,
  };

  static const Map<String, String> _statusLabels = {
    'draft': 'مسودة',
    'sent': 'مرسل',
    'accepted': 'مقبول',
    'rejected': 'مرفوض',
    'expired': 'منتهي الصلاحية',
    'converted': 'تم التحويل',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedStatus = _statusTabs[_tabController.index].key);
        _applyFilters();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper();
      _allQuotations = await db.getAllQuotations();
      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = _allQuotations;
    if (_selectedStatus != 'all') {
      filtered = filtered.where((q) => q['status'] == _selectedStatus).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((q) {
        final num = (q['quotation_number'] ?? '').toString().toLowerCase();
        final name = (q['customer_name'] ?? '').toString().toLowerCase();
        return num.contains(query) || name.contains(query);
      }).toList();
    }
    setState(() => _filteredQuotations = filtered);
  }

  Future<void> _deleteQuotation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف عرض السعر'),
        content: const Text('هل أنت متأكد من حذف عرض السعر هذا؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper().deleteQuotation(id);
      _loadData();
    }
  }

  Future<void> _changeStatus(String id, String newStatus) async {
    await DatabaseHelper().updateQuotation(id, {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    });
    _loadData();
  }

  void _showStatusMenu(String quotationId, String currentStatus) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('تغيير حالة عرض السعر', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const Divider(),
              ..._statusLabels.entries.where((e) => e.key != currentStatus).map((entry) => ListTile(
                leading: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(color: _statusColors[entry.key], shape: BoxShape.circle),
                ),
                title: Text(entry.value),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeStatus(quotationId, entry.key);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: AppBar(
          title: const Text('عروض الأسعار'),
          centerTitle: true,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            tabs: _statusTabs.map((e) => Tab(text: e.value)).toList(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // Search bar
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: TextField(
                          onChanged: (v) { _searchQuery = v; _applyFilters(); },
                          decoration: InputDecoration(
                            hintText: 'بحث برقم العرض أو اسم العميل...',
                            prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
                            filled: true,
                            fillColor: isDark ? AppColors.darkSurface : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          ),
                        ),
                      ),
                    ),
                    // Summary
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: _buildSummaryCard(theme, isDark),
                      ),
                    ),
                    // Quotations list
                    if (_filteredQuotations.isEmpty)
                      SliverFillRemaining(
                        child: _buildEmptyState(isDark),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _buildQuotationCard(ctx, _filteredQuotations[i], isDark, theme),
                            childCount: _filteredQuotations.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateQuotationScreen()),
            );
            if (result == true) _loadData();
          },
          icon: const Icon(PhosphorIconsRegular.plus, color: Colors.white),
          label: const Text('عرض سعر جديد', style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, bool isDark) {
    final totalValue = _filteredQuotations.fold<double>(0, (sum, q) => sum + ((q['total'] as num?)?.toDouble() ?? 0));
    final acceptedCount = _filteredQuotations.where((q) => q['status'] == 'accepted').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إجمالي العروض', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text('${_filteredQuotations.length} عرض', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('القيمة الإجمالية', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.format(totalValue), style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المقبولة', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text('$acceptedCount', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotationCard(BuildContext ctx, Map<String, dynamic> q, bool isDark, ThemeData theme) {
    final status = q['status'] ?? 'draft';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final total = (q['total'] as num?)?.toDouble() ?? 0;
    final currency = q['currency'] ?? 'YER';
    final createdAt = q['created_at'] != null ? DateTime.tryParse(q['created_at']) : null;

    return Dismissible(
      key: ValueKey(q['id']),
      direction: DismissDirection.startToEnd,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        await _deleteQuotation(q['id']);
        return true;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.divider),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: InkWell(
          onTap: () => _showStatusMenu(q['id'], status),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(PhosphorIconsRegular.fileText, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            q['quotation_number'] ?? '',
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _statusLabels[status] ?? status,
                              style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        q['customer_name'] ?? 'بدون عميل',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(total),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currency,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsRegular.fileText, size: 64, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('لا توجد عروض أسعار', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('اضغط على + لإنشاء عرض سعر جديد', style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
        ],
      ),
    );
  }
}
