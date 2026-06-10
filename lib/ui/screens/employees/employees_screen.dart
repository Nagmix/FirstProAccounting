import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/helpers/currency_constants.dart';
import '../../../core/helpers/avatar_helper.dart';
import '../../../core/helpers/delete_helper.dart';
import '../../../data/datasources/repositories/employee_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../widgets/empty_state.dart';
import 'employee_detail_screen.dart';

/// Professional employees management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name or phone.
/// - Tab bar: الكل / مدينون / دائنون.
/// - Employee list with avatar, name, job title, phone, and balance.
/// - Compact filter button for currency selection.
/// - FAB for adding a new employee via [AddEmployeeSheet].
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;

  // Currency filter state
  String _selectedCurrency = 'YER';
  bool _isBalancesLoading = false;
  Map<int, double> _currencyBalances = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _searchQuery = _searchController.text.trim());
      });
    });
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    try {
      final employees =
          await locator<ReferenceDataRepository>().getAllEmployees();
      if (mounted) {
        setState(() {
          _employees = employees;
          _isLoading = false;
        });
        _loadCurrencyBalances();
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

  // ── Currency balance loading ──────────────────────────────────
  Future<void> _loadCurrencyBalances() async {
    setState(() => _isBalancesLoading = true);
    try {
      final newBalances = <int, double>{};
      final repo = locator<EmployeeRepository>();

      final futures = _employees.map((e) async {
        final id = e['id'] as int?;
        if (id != null) {
          final balance = await repo.getEmployeeBalanceForCurrency(
            id,
            _selectedCurrency,
          );
          return MapEntry(id, balance);
        }
        return null;
      });

      final results = await Future.wait(futures);
      for (final entry in results) {
        if (entry != null) {
          newBalances[entry.key] = entry.value;
        }
      }

      if (mounted) {
        setState(() {
          _currencyBalances = newBalances;
          _isBalancesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isBalancesLoading = false);
    }
  }

  void _onCurrencyChanged(String currency) {
    setState(() => _selectedCurrency = currency);
    _loadCurrencyBalances();
  }

  // ── Filter logic ──────────────────────────────────────────────
  List<Map<String, dynamic>> _filterEmployees(int tabIndex) {
    var filtered = _employees;

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        final phone = (e['phone'] as String? ?? '').toLowerCase();
        final jobTitle = (e['job_title'] as String? ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q) || jobTitle.contains(q);
      }).toList();
    }

    // Apply tab filter based on balance
    switch (tabIndex) {
      case 1: // مدينون — negative balance (عليه)
        filtered = filtered.where((e) {
          final id = e['id'] as int?;
          if (id == null) return false;
          final balance = _currencyBalances[id] ?? 0.0;
          return balance < 0;
        }).toList();
        break;
      case 2: // دائنون — positive balance (له)
        filtered = filtered.where((e) {
          final id = e['id'] as int?;
          if (id == null) return false;
          final balance = _currencyBalances[id] ?? 0.0;
          return balance > 0;
        }).toList();
        break;
      // case 0: الكل – no additional filter
    }

    return filtered;
  }

  // ── Open add-employee bottom sheet ────────────────────────────
  Future<void> _showAddEmployeeSheet({Map<String, dynamic>? employee}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddEmployeeSheet(employee: employee),
    );
    _loadEmployees();
  }

  // ── Delete employee ───────────────────────────────────────────
  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final name = employee['name'] as String? ?? '';
    final confirmed = await DeleteHelper.showDeleteConfirmation(
      context: context,
      entityType: 'الموظف',
      entityName: name,
    );
    if (confirmed) {
      await locator<ReferenceDataRepository>()
          .deleteEmployee(employee['id'] as int);
      if (mounted) {
        DeleteHelper.showDeleteSuccess(context, 'الموظف', name);
      }
      _loadEmployees();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final currentSymbol = CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفين'),
        actions: [
          // Filter button (currency)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              avatar: Icon(Icons.currency_exchange, size: 16, color: AppColors.primary),
              label: Text(
                '$currentSymbol $_selectedCurrency',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
              onPressed: () => CurrencyConstants.showCurrencyFilterPopup(
                context: context,
                selectedCurrency: _selectedCurrency,
                onSelected: _onCurrencyChanged,
              ),
              backgroundColor: AppColors.primary.withOpacity(0.08),
              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'إضافة موظف',
            onPressed: () => _showAddEmployeeSheet(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'مدينون'),
            Tab(text: 'دائنون'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث عن موظف بالاسم أو الهاتف...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Summary bar ───────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isLight ? AppColors.border : AppColors.darkBorder, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_employees.length} موظف',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (_isBalancesLoading)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else ...[
                        Icon(Icons.account_balance_wallet, size: 16, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          'العملة: $_selectedCurrency',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textHint,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calculate, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'الإجمالي: ${CurrencyFormatter.formatValue(_currencyBalances.values.fold(0.0, (sum, b) => sum + b))} $currentSymbol',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Employee list ─────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterEmployees(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.people
                              : tabIndex == 1
                                  ? Icons.trending_down
                                  : Icons.trending_up,
                          title: tabIndex == 0
                              ? 'لا يوجد موظفين'
                              : tabIndex == 1
                                  ? 'لا يوجد موظفين مدينون'
                                  : 'لا يوجد موظفين دائنون',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة موظفين جدد لبدء إدارة حساباتك'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel: tabIndex == 0 ? 'إضافة موظف' : null,
                          onAction: tabIndex == 0 ? () => _showAddEmployeeSheet() : null,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _loadEmployees,
                        color: AppColors.primary,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 80, top: 2),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                          final employee = filtered[index];
                          final id = employee['id'] as int?;
                          final displayBalance = _currencyBalances[id] ?? 0.0;
                          return _EmployeeCard(
                            employee: employee,
                            avatarColor: AvatarHelper.avatarColor(employee['name'] as String? ?? ''),
                            displayBalance: displayBalance,
                            currencySymbol: CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي',
                            isLight: isLight,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EmployeeDetailScreen(employee: employee),
                                ),
                              ).then((_) => _loadEmployees());
                            },
                            onDelete: () => _deleteEmployee(employee),
                          );
                        },
                        )
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEmployeeSheet(),
        tooltip: 'إضافة موظف',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة موظف'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  EMPLOYEE CARD — Modern, Professional Design (matches _CustomerCard)
// ═══════════════════════════════════════════════════════════════════
class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.avatarColor,
    required this.displayBalance,
    required this.currencySymbol,
    required this.isLight,
    this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> employee;
  final Color avatarColor;
  final double displayBalance;
  final String currencySymbol;
  final bool isLight;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = employee['name'] as String? ?? '';
    final phone = employee['phone'] as String? ?? '';
    final jobTitle = employee['job_title'] as String? ?? '';
    final isDebit = displayBalance < 0;
    final isCredit = displayBalance > 0;
    final balanceColor = isDebit
        ? AppColors.error
        : isCredit
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    final balanceAbs = CurrencyFormatter.formatValue(displayBalance.abs());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? AppColors.border.withOpacity(0.5) : AppColors.darkBorder.withOpacity(0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.04 : 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          onLongPress: onDelete,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ── Avatar ───────────────────────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [avatarColor, avatarColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: avatarColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Name, job title, phone ──────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Job title row
                      if (jobTitle.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.work,
                              size: 13,
                              color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              jobTitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
                              ),
                            ),
                            if (phone.isNotEmpty) const SizedBox(width: 8),
                          ],
                        ),
                      // Phone row
                      if (phone.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 13,
                              color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              phone,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ── Balance Section - الرصيد with color ──────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: displayBalance != 0
                          ? [balanceColor.withOpacity(0.12), balanceColor.withOpacity(0.04)]
                          : [Colors.grey.withOpacity(0.06), Colors.grey.withOpacity(0.02)],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: displayBalance != 0 ? balanceColor.withOpacity(0.25) : AppColors.border.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDebit ? Icons.trending_down : isCredit ? Icons.trending_up : Icons.remove,
                        size: 14,
                        color: displayBalance != 0 ? balanceColor : AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$balanceAbs $currencySymbol',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: displayBalance != 0 ? balanceColor : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // ── Arrow icon ──────────────────────────────────
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 12,
                    color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD EMPLOYEE SHEET – matches AddCustomerSheet pattern
// ═══════════════════════════════════════════════════════════════════
class AddEmployeeSheet extends StatefulWidget {
  final Map<String, dynamic>? employee;

  const AddEmployeeSheet({super.key, this.employee});

  @override
  State<AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<AddEmployeeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _balanceController = TextEditingController();
  final _notesController = TextEditingController();

  String _balanceType = 'credit'; // 'credit' (له) or 'debit' (عليه)
  String _openingBalanceCurrency = 'YER';
  bool _isSaving = false;

  static const _currencyInfo = {
    'YER': {'symbol': 'ر.ي', 'label': 'ريال يمني'},
    'SAR': {'symbol': 'ر.س', 'label': 'ريال سعودي'},
    'USD': {'symbol': '\$', 'label': 'دولار أمريكي'},
  };

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      final e = widget.employee!;
      _nameController.text = e['name'] as String? ?? '';
      _phoneController.text = e['phone'] as String? ?? '';
      _jobTitleController.text = e['job_title'] as String? ?? '';
      _balanceController.text =
          MoneyHelper.readMoney(e['balance']).toStringAsFixed(2);
      _balanceType = e['balance_type'] as String? ?? 'credit';
      _openingBalanceCurrency = e['currency'] as String? ?? 'YER';
      _notesController.text = e['notes'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _jobTitleController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now().toIso8601String();
      final balance = double.tryParse(_balanceController.text) ?? 0.0;
      final isEditing = widget.employee != null;

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'job_title': _jobTitleController.text.trim().isEmpty
            ? null
            : _jobTitleController.text.trim(),
        'balance': balance,
        'balance_type': _balanceType,
        'currency': _openingBalanceCurrency,
        'account_id': null,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'is_active': 1,
        'updated_at': now,
      };

      if (isEditing) {
        await locator<ReferenceDataRepository>()
            .updateEmployee(widget.employee!['id'] as int, data);
      } else {
        data['created_at'] = now;
        if (balance > 0) {
          data['opening_balance_currency'] = _openingBalanceCurrency;
        }
        await locator<EmployeeRepository>()
            .insertEmployeeWithOpeningBalance(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'تم تعديل الموظف بنجاح'
                : 'تم إضافة الموظف بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isEditing = widget.employee != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل موظف' : 'إضافة موظف جديد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 20),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + bottomPadding + 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _jobTitleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'المسمى الوظيفي',
                    prefixIcon: Icon(Icons.work),
                  ),
                ),
                const SizedBox(height: 14),

                // ── القيد الافتتاحي Section ───────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isLight ? AppColors.border : AppColors.darkBorder,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section header
                      Row(
                        children: [
                          Icon(Icons.book_outlined,
                              size: 20, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'القيد الافتتاحي',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Amount field
                      TextFormField(
                        controller: _balanceController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'))
                        ],
                        decoration: InputDecoration(
                          labelText: 'الرصيد الافتتاحي',
                          prefixIcon: const Icon(Icons.calculate),
                          suffixText: _currencyInfo[_openingBalanceCurrency]
                                  ?['symbol'] ??
                              AppConstants.currency,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Currency dropdown
                      DropdownButtonFormField<String>(
                        value: _openingBalanceCurrency,
                        decoration: const InputDecoration(
                          labelText: 'عملة القيد',
                          prefixIcon: Icon(Icons.currency_exchange),
                        ),
                        items: _currencyInfo.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                      '${e.value['label']} (${e.value['symbol']})'),
                                ))
                            .toList(),
                        onChanged: isEditing
                            ? null
                            : (v) => setState(() => _openingBalanceCurrency = v!),
                      ),
                      const SizedBox(height: 14),

                      // Balance direction toggle
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'اتجاه الرصيد الافتتاحي',
                              style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: _balanceType == 'credit'
                                      ? AppColors.success
                                      : AppColors.error),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _balanceType = 'credit'),
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'credit'
                                            ? AppColors.success.withOpacity(0.1)
                                            : Colors.transparent,
                                        borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(9),
                                            bottomRight: Radius.circular(9)),
                                      ),
                                      child: Text(
                                        'له',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'credit'
                                              ? AppColors.success
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _balanceType = 'debit'),
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'debit'
                                            ? AppColors.error.withOpacity(0.1)
                                            : Colors.transparent,
                                        borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(9),
                                            bottomLeft: Radius.circular(9)),
                                      ),
                                      child: Text(
                                        'عليه',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'debit'
                                              ? AppColors.error
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Notes field
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    prefixIcon: Icon(Icons.notes),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Save Button (visible at bottom of form) ────────────
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 20),
                  label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
